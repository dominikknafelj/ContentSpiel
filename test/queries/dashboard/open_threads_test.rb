require "test_helper"

class Dashboard::OpenThreadsTest < ActiveSupport::TestCase
  # The statements a read of the rows and of `more_records` takes, for one row
  # as for eight.
  STATEMENTS = 6

  setup do
    @page = create_page(title: "Pricing")
    @block = @page.content_blocks.create!(block_type: "rich_text", position: 0)
    @post = create_post(title: "Hello")
    @quiet = create_post(title: "Quiet")
  end

  def note(subject) = as(users(:two)) { Notes::Start.call(subject, body: "A note") }.record

  def open_threads(user = users(:reader), **options) = Dashboard::OpenThreads.new(actor: user, channel: :admin, **options)

  test "records with open threads, the most recently active first, with their counts" do
    note(@page)
    travel_to(1.minute.from_now) { note(@post) }
    travel_to(2.minutes.from_now) { note(@block) }
    as(users(:two)) { Notes::Resolve.call(note(@quiet)) }

    rows = open_threads.rows

    assert_equal [ [ @page, "page", "Pricing", 2 ], [ @post, "post", "Hello", 1 ] ], rows.map { |row| [ row.record, row.kind, row.title, row.count ] }
    assert_equal [ :admin_page_path, [ @page.id ], { notes: "open" } ], rows.first.route.then { |route| [ route.name, route.args, route.params ] }
    assert_equal [ [ "Page", @page.id ], [ "Post", @post.id ] ].to_set, open_threads.record_keys
  end

  # A row says who wrote last, as "type · last author · time".
  test "a row names who wrote last among the record's open threads, a resolved thread's reply not counted, and nobody once the author's id is gone" do
    on_page = note(@page)
    travel_to(1.minute.from_now) { as(users(:one)) { Notes::Reply.call(note(@block), body: "Later, on a block") } }
    done = travel_to(2.minutes.from_now) { note(@page) }
    travel_to(3.minutes.from_now) { as(users(:reader)) { Notes::Reply.call(done, body: "Last, but on a thread that is then resolved") } }
    as(users(:two)) { Notes::Resolve.call(done) }
    gone = User.create!(email_address: "gone@example.com", password: "a-long-password-1")
    travel_to(4.minutes.from_now) { on_post = note(@post); Notes::Message.create!(thread: on_post, author_id: gone.id, body: "Bye", created_at: 5.minutes.from_now) }
    Notes::Message.where(author_id: gone.id).update_all(author_id: nil) # version: none (a test's own setup: what the foreign key does when the author is deleted)

    by_record = open_threads.rows.index_by(&:record)

    assert_equal [ users(:one), users(:one).id ], by_record[@page].then { |row| [ row.last_author, row.last_author_id ] }
    assert_equal [ nil, nil ], by_record[@post].then { |row| [ row.last_author, row.last_author_id ] }
    assert on_page.reload.open?
  end

  test "an image's row leads to the Media screen with the image chosen, for someone who may open the library" do
    asset = create_media_asset
    note(asset)

    assert_empty open_threads.rows # Read only has no media.upload
    row = open_threads(users(:two)).rows.first
    assert_equal [ asset, "media", :admin_media_path, [], { selected: asset.id } ], [ row.record, row.kind, row.route.name, row.route.args, row.route.params ]
  end

  test "narrowed to records, only their open threads are counted" do
    note(@page)
    note(@block)
    note(@post)
    travel_to(1.minute.from_now) { note(@quiet) }
    asset = create_media_asset
    note(asset)
    narrowed = Dashboard::OpenThreads.new(actor: users(:two), channel: :admin, records: [ @page, @quiet, asset ])

    statements = capture_sql { narrowed.rows }
    assert_equal [ [ @quiet, 1 ], [ @page, 2 ], [ asset, 1 ] ].to_set, narrowed.rows.map { |row| [ row.record, row.count ] }.to_set
    assert_empty statements.grep(/\ASELECT "(pages|posts|media_assets)"\.\*/), "the records handed in are not read again"
    assert_equal @quiet, narrowed.rows.first.record
    assert_equal [ [ "Page", @page.id ], [ "Post", @quiet.id ], [ "Media::Asset", asset.id ] ].to_set, narrowed.record_keys
    assert_empty Dashboard::OpenThreads.new(actor: users(:two), channel: :admin, records: []).rows
    assert_equal 4, Dashboard::OpenThreads.new(actor: users(:two), channel: :admin).record_keys.size
  end

  test "five rows, read-scoped, in a constant number of statements" do
    posts = Array.new(7) { |index| create_post(title: "Post #{index}") }
    posts.first(2).each { |post| note(post) }
    stranger = User.create!(email_address: "stranger@example.com", password: "a-long-password-1")
    open_threads.rows # warm-up: the fixture user's grants are read once and kept on the object
    few = capture_sql { open_threads.then { |query| [ query.rows, query.record_keys.size ] } }.size
    posts.each { |post| note(post) }

    assert_equal 5, open_threads.rows.size
    assert_equal 7, open_threads.record_keys.size
    assert_equal few, capture_sql { open_threads.then { |query| [ query.rows, query.record_keys.size ] } }.size
    assert_equal [ [], 0 ], open_threads(stranger).then { |query| [ query.rows, query.record_keys.size ] }
  end

  test "each row names the newest two people who wrote on its open threads and how many wrote, in the same statements for one row as for eight" do
    page_note = note(@page)
    travel_to(1.minute.from_now) { as(users(:one)) { Notes::Reply.call(page_note, body: "Second") } }
    travel_to(2.minutes.from_now) { as(users(:reader)) { Notes::Reply.call(page_note, body: "Third") } }
    travel_to(3.minutes.from_now) { as(users(:two)) { Notes::Reply.call(page_note, body: "Fourth, by the first writer again") } }
    resolved = travel_to(4.minutes.from_now) { note(@post) }
    travel_to(5.minutes.from_now) { as(users(:one)) { Notes::Reply.call(resolved, body: "Not shown once resolved") } }
    as(users(:two)) { Notes::Resolve.call(resolved) }
    open_threads.rows # warm-up: the fixture user's grants are read once and kept on the object

    assert_equal [ [], 0 ], open_threads.rows.sole.then { |plain| [ plain.authors, plain.author_count ] }, "nobody is read unless asked"
    row = open_threads(with_authors: true).rows.sole
    assert_equal [ users(:two), users(:reader) ], row.authors
    assert_equal 3, row.author_count

    asked = -> { ActiveRecord::Base.uncached { open_threads(with_authors: true).then { |query| [ query.rows, query.more_records ] } } }
    one = nil
    assert_queries_count(STATEMENTS) { one = asked.call }
    Array.new(7) { |index| create_page(title: "Many #{index}") }.each { |page| note(page) }
    eight = nil
    assert_queries_count(STATEMENTS) { eight = open_threads(limit: 8, with_authors: true).then { |query| ActiveRecord::Base.uncached { [ query.rows, query.more_records ] } } }
    assert_equal [ 1, 8 ], [ one.first.size, eight.first.size ]
  end

  test "more_records is the readable records with open threads beyond the rows" do
    posts = Array.new(5) { |index| create_post(title: "More #{index}") }
    posts.each { |post| note(post) }
    note(@page)
    hidden = create_post(title: "Trashed later")
    note(hidden)
    hidden.update!(trashed_at: Time.current)

    query = Dashboard::OpenThreads.new(actor: users(:two), channel: :admin, limit: 4)

    assert_equal 4, query.rows.size
    assert_equal 2, query.more_records
    assert_equal 0, Dashboard::OpenThreads.new(actor: users(:two), channel: :admin, limit: 8).more_records
    assert_equal 0, open_threads(User.create!(email_address: "stranger2@example.com", password: "a-long-password-1")).more_records
  end

  test "a row's people are the newest two who wrote on its open threads the viewer may read, and the more line counts only readable records" do
    asset = create_media_asset
    note(asset)
    as(users(:one)) { Notes::Reply.call(Notes::Thread.find_by!(container_type: "Media::Asset", container_id: asset.id), body: "Only the owner can read this image") }
    on_page = note(@page)
    travel_to(1.minute.from_now) { as(users(:one)) { Notes::Reply.call(on_page, body: "Second") } }
    done = travel_to(2.minutes.from_now) { as(users(:one)) { Notes::Start.call(@page, body: "Resolved soon") }.record }
    gone = User.create!(email_address: "writer-of-resolved@example.com", password: "a-long-password-1")
    Notes::Message.create!(thread: done, author: gone, body: "Only on a resolved thread", created_at: 3.minutes.from_now)
    as(users(:two)) { Notes::Resolve.call(done) }
    trashed = create_post(title: "Trashed later")
    note(trashed)
    trashed.update!(trashed_at: Time.current)

    reader = open_threads(users(:reader), with_authors: true, limit: 1)
    row = reader.rows.sole

    assert_equal @page, row.record
    assert_equal [ users(:one), users(:two) ], row.authors
    assert_equal 2, row.author_count, "neither the resolved thread's writer nor the image's counts"
    assert_equal 0, reader.more_records, "the image the viewer may not read and the trashed post are not 'more'"

    owner = open_threads(users(:two), with_authors: true, limit: 1)
    assert_equal 1, owner.more_records, "for someone who may read the image it is one more record"
  end
end
