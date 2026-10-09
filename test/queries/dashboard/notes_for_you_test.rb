require "test_helper"

class Dashboard::NotesForYouTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @post = create_post(title: "Hello")
    @asset = create_media_asset
    users(:two).update!(name: "Dana")
    @me = users(:reader)
    AccessControl::Grant.find_or_create_by!(group: access_control_groups(:read_only), permission: "media.upload") { |grant| grant.scope = {} }
  end

  def inbox(user = @me) = Dashboard::NotesForYou.new(actor: user, channel: :admin)

  def mention(subject, body = "Look, @[#{@me.id}]") = as(users(:two)) { Notes::Start.call(subject, body: body) }.record

  test "a row says who did what, the note's first words and where, and leads to the record with its notes open at the thread" do
    thread = mention(@block, "Is @[#{@me.id}] sure about #{"this " * 40}")

    row = inbox.rows.first

    assert_equal [ "mention", users(:two), "page", "Pricing", @block, true, thread.id ], [ row.reason, row.by, row.kind, row.title, row.block, row.unread, row.thread_id ]
    assert row.excerpt.start_with?("Is @reader@example.com sure about this")
    assert_operator row.excerpt.length, :<=, 140
    assert_equal [ :admin_page_path, [ @page.id ], { notes: "open", thread: thread.id } ], [ row.route.name, row.route.args, row.route.params ]
  end

  test "a post and an image lead to their own screens" do
    on_post = mention(@post)
    on_asset = mention(@asset)

    routes = inbox.rows.index_by(&:thread_id).transform_values { |row| [ row.kind, row.route.name, row.route.params ] }

    assert_equal [ "post", :admin_post_path, { notes: "open", thread: on_post.id } ], routes[on_post.id]
    assert_equal [ "media", :admin_media_path, { selected: @asset.id, thread: on_asset.id } ], routes[on_asset.id]
  end

  test "unread first, then newest; the count is the unread ones" do
    old = mention(@page)
    read = travel_to(1.minute.from_now) { mention(@post) }
    newest = travel_to(2.minutes.from_now) { mention(@asset) }
    Notes::Delivery.where(user: @me, thread: read).update_all(read_at: Time.current) # version: none (a test's own setup)

    assert_equal [ newest.id, old.id, read.id ], inbox.rows.map(&:thread_id)
    assert_equal [ 2, 3 ], [ inbox.unread_count, inbox.total ]
    assert_equal [ old.id ], inbox.rows(limit: 1, offset: 1).map(&:thread_id)
  end

  # `Notes::Deliveries` REUSES a person's row for a thread's first message
  # when the thread is resolved or reopened: it keeps its `created_at`. The
  # inbox dates a row by when it last had something to say, or the news of a
  # resolve would be buried under everything written since the mention.
  test "a delivery written long ago and used again now sorts first and carries the new time" do
    old = travel_to(3.days.ago) { mention(@page) }
    travel_to(1.day.ago) { mention(@post) }
    as(@me) { Notes::MarkRead.call }
    resolved_at = Time.current.change(usec: 0)

    travel_to(resolved_at) { as(users(:two)) { Notes::Resolve.call(old) } }

    assert_equal 2, Notes::Delivery.where(user: @me).count # the row was reused, not added
    first = inbox.rows.first
    assert_equal [ old.id, "resolved", true, resolved_at ], [ first.thread_id, first.reason, first.unread, first.at ]
    assert_operator Notes::Delivery.find(first.id).created_at, :<, 2.days.ago
  end

  # Reading is not news: a row read today keeps the time of what it told.
  test "reading a row does not move it or change its time" do
    old = travel_to(3.days.ago) { mention(@page) }
    newer = travel_to(1.day.ago) { mention(@post) }
    before = inbox.rows.map(&:at)

    as(@me) { Notes::MarkRead.call(thread: old) }
    as(@me) { Notes::MarkRead.call }

    assert_equal [ [ newer.id, old.id ], before ], [ inbox.rows.map(&:thread_id), inbox.rows.map(&:at) ]
    assert_equal 0, inbox.unread_count
  end

  test "a resolve names who resolved, a reply who replied" do
    thread = mention(@page)
    as(users(:one)) { Notes::Reply.call(thread, body: "On it") }
    assert_equal [ "reply", users(:one) ], inbox.rows.first.then { |row| [ row.reason, row.by ] }

    as(users(:two)) { Notes::Resolve.call(thread) }
    assert_equal [ "resolved", users(:two) ], inbox.rows.find { |row| row.reason == "resolved" }.then { |row| [ row.reason, row.by ] }
  end

  test "a reopen names nobody, and a note whose author is gone names nobody either" do
    thread = mention(@page)
    as(users(:two)) { Notes::Resolve.call(thread) }
    as(users(:two)) { Notes::Reopen.call(thread) }
    assert_equal [ "reopened", nil, nil ], inbox.rows.first.then { |row| [ row.reason, row.by, row.by_id ] }

    other = mention(@post)
    other.first_message.update_columns(author_id: nil) # version: none (a test's own setup: what the foreign key does when the author is deleted)
    assert_equal [ "mention", nil, nil ], inbox.rows.find { |row| row.thread_id == other.id }.then { |row| [ row.reason, row.by, row.by_id ] }
  end

  test "a delivery on a record I can no longer read, or that is in the trash, is not shown and not counted" do
    mention(@page)
    mention(@post)
    @post.update!(trashed_at: Time.current)
    assert_equal [ [ "page" ], 1 ], [ inbox.rows.map(&:kind), inbox.unread_count ]

    AccessControl::Membership.where(user: @me).destroy_all
    assert_equal [ [], 0, 0 ], [ inbox.rows, inbox.unread_count, inbox.total ]
    assert_equal 2, Notes::Delivery.where(user: @me).count # the rows stay
  end

  # One right at a time (notes spec §3.3): the row stays in the table and
  # shows nowhere. An image has no read right of its own: `media.upload`
  # opens the library.
  { "page" => "pages.read", "post" => "posts.read", "media" => "media.upload" }.each do |kind, permission|
    test "losing #{permission} hides what was addressed to me on a #{kind} and nothing else, and no row is deleted" do
      [ @page, @post, @asset ].each { |subject| mention(subject) }
      assert_equal [ %w[media page post], 3 ], [ inbox.rows.map(&:kind).sort, inbox.unread_count ]

      AccessControl::Grant.where(group: access_control_groups(:read_only), permission: permission).destroy_all

      left = %w[media page post] - [ kind ]
      assert_equal [ left, 2, 2 ], [ inbox.rows.map(&:kind).sort, inbox.unread_count, inbox.total ]
      assert_nil inbox.find(Notes::Delivery.joins(:thread).find_by!(user: @me, note_threads: { container_type: Dashboard::NotesForYou::KINDS.key(kind) }).id)
      assert_equal 3, Notes::Delivery.where(user: @me).count
    end
  end

  test "find answers one of my deliveries and nobody else's" do
    mention(@page)
    mine = Notes::Delivery.find_by!(user: @me)

    assert_equal mine.id, inbox.find(mine.id).id
    assert_nil inbox(users(:author)).find(mine.id)
    assert_nil inbox.find(0)
  end

  test "the unread count is one statement" do
    mention(@page)

    statements = capture_sql { assert_equal 1, inbox.unread_count }

    assert_equal 1, statements.size
    assert_match(/\ASELECT COUNT\(\*\) FROM "note_deliveries"/, statements.first)
  end

  test "it costs the same statements for two rows as for five" do
    2.times { mention(@block) }
    inbox.rows # warm-up: the fixture user's grants are read once and kept on the object
    few = capture_sql { inbox.rows; inbox.unread_count }.size
    [ @page, @post, @asset ].each { |subject| mention(subject) }

    assert_equal few + 2, capture_sql { inbox.rows; inbox.unread_count }.size # the posts and the images: one read per kind of record on the page
  end
end
