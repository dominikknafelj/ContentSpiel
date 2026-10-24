require "test_helper"

class Dashboard::ActivityTest < ActiveSupport::TestCase
  setup { @me = users(:one) }

  def activity(actor = @me, limit: 15) = Current.set(actor:, channel: :admin) { Dashboard::Activity.new(actor:, limit:) }

  # `[words before the subject, the subject, words after it]` -- the wording is
  # `Audit::Sentence`'s now, as parts.
  def words(row)
    parts = row.sentence.parts
    at = parts.index { |part| part.kind == :subject }
    [ parts[0...at].map(&:text).join.strip, parts[at].text, parts[(at + 1)..].map(&:text).join ]
  end

  def sentences(actor = @me)
    activity(actor).rows.map { |row| [ row.sentence.actor.you ? "You" : row.sentence.actor.user&.display_name, *words(row) ] }
  end

  test "lists content events only, never access.denied, sessions, users, groups, tokens or settings" do
    post = Current.set(actor: @me, channel: :admin) { create_post(title: "Hello", published: false) }
    Audit.record("access.denied", subject: post)
    Audit.record("session.signed_in", subject: nil)
    Audit.record("user.updated", subject: @me)
    Audit.record("settings.updated", subject: site_settings(:default))

    assert_equal [ [ "post.created" ] ], activity.rows.map { |row| [ row.event.action ] }
  end

  test "reads one whole sentence per action" do
    post = as(@me) { create_post(title: "Hello", published: false) }
    as(@me) { Posts::Save.call(post, attributes: { published: true }) }
    as(@me) { Posts::Save.call(post, attributes: { published_at: Time.zone.local(2031, 10, 6, 9) }) }

    # The viewer's own events read "You" (the log's wording, `Audit::Sentence`).
    assert_includes sentences, [ "You", "published", "Hello", "" ]
    assert_includes sentences, [ "You", "scheduled", "Hello", " for 6 Oct" ]
    assert_includes sentences, [ "You", "created", "Hello", "" ]
  end

  test "an event about a post the viewer can't read is absent, not anonymised" do
    resume = as(@me) { create_post(title: "Secret", content_type: "resume_entry", published: false) }
    blog = as(@me) { create_post(title: "Open", published: false) }
    group = AccessControl::Group.create!(name: "Blog readers")
    group.grants.create!(permission: "posts.read", scope: { "content_types" => [ "blog" ] })
    reader = User.create!(email_address: "blog-reader@example.com", password: "password12345")
    AccessControl::Membership.create!(user: reader, group: group)

    assert_equal [ blog ], activity(reader).rows.map(&:record)
    assert_includes activity(@me).rows.map(&:record), resume
  end

  test "a trashed record's events are all absent, its trashed event included, and return on restore" do
    post = as(@me) { create_post(title: "Gone soon", published: false) }
    as(@me) { Trash::Move.call(post) }
    assert_empty activity.rows

    as(@me) { Trash::Restore.call(post.reload) }
    assert_equal %w[post.restored post.trashed post.created], activity.rows.map { |row| row.event.action }
    assert_equal [ "moved", "Gone soon", " to the trash" ], words(activity.rows.second)
  end

  test "a block event reads as the block, named, on the page, and points at the page" do
    page = as(@me) { create_page(title: "About") }
    block = as(@me) { ContentBlocks::Save.call(ContentBlock.new(owner: page, block_type: "rich_text")).record }
    row = activity.rows.find { |r| r.event.action.start_with?("block.") }

    # Unified with the audit log: a created block is "added a <type> block to".
    assert_equal [ "added a Rich text block to", "About", "" ], words(row)
    assert_equal page, row.record
    assert block.persisted?
  end

  # Task 16's d1: only a page or post can be "scheduled"; a block event whose
  # only change names published_at must not be a KeyError on the landing page.
  test "a block event that only names a future published_at still reads as a block edit" do
    page = as(@me) { create_page(title: "About") }
    block = as(@me) { ContentBlocks::Save.call(ContentBlock.new(owner: page, block_type: "rich_text")).record }
    as(@me) { Audit.record("block.updated", subject: block, field_changes: { "published_at" => [ nil, Time.zone.local(2031, 10, 6, 9).iso8601 ] }) }

    rows = activity.rows.select { |r| r.event.action == "block.updated" }
    assert_equal 1, rows.size
    assert_equal "edited a block on", words(rows.first).first
  end

  # Task 16's d3: the class comment promises "a viewer with no grants runs no
  # query"; the old `1=0` condition still ran one.
  test "a viewer who can read nothing sends no query at all" do
    as(@me) { create_post(title: "Hidden from them") }
    nobody = User.create!(email_address: "nogrants@example.com", password: "a long enough password")
    queries = []
    counter = ->(*, payload) { queries << payload[:sql] unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:cached] }
    rows = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { activity(nobody).rows }

    assert_empty rows
    assert_empty queries.grep(/audit_events/)
  end

  test "a coalesced event carries both ends of its span" do
    post = as(@me) { create_post(title: "Typing", published: false) }
    first = nil
    travel_to 2.minutes.from_now do
      as(@me) { Posts::Save.call(post, translations: { Locales.default => { title: "Typing 1" } }) }
    end
    travel_to 5.minutes.from_now do
      as(@me) { Posts::Save.call(post, translations: { Locales.default => { title: "Typing 2" } }) }
    end
    row = activity.rows.find { |r| r.event.action == "post.updated" }
    first = row.at

    assert_not_nil row.span_end
    assert_operator row.span_end, :>, first
    assert_nil activity.rows.find { |r| r.event.action == "post.created" }.span_end
  end

  test "a nil actor reads System and a deleted user reads a deleted user" do
    as(nil, channel: :system) { create_post(title: "By the system", published: false) }
    gone = User.create!(email_address: "gone@example.com", password: "password12345")
    AccessControl::Membership.create!(user: gone, group: access_control_groups(:admin))
    as(gone) { create_post(title: "By a ghost", published: false) }
    gone.destroy!

    # Facts, not a label: the component names them (`Admin::Ui::UserNameComponent`).
    actors = activity.rows.to_h { |row| [ row.record.title, row.sentence.actor ] }
    assert_nil actors["By the system"].user
    assert_nil actors["By the system"].user_id
    assert_nil actors["By a ghost"].user
    assert_equal gone.id, actors["By a ghost"].user_id
  end

  test "a change through an API token is the user's, carries via_label, and the name outlives the token" do
    token, = ApiToken.generate!(@me, group: access_control_groups(:admin), name: "Claude desktop")
    as(token, channel: :mcp) { create_post(title: "Via MCP", published: false) }
    row = activity.rows.first

    assert_equal "Claude desktop", row.sentence.actor.via_label
    assert_equal @me, row.sentence.actor.user
    assert row.sentence.actor.you
    ApiToken.delete_all
    assert_equal "Claude desktop", activity.rows.first.sentence.actor.via_label
  end

  test "images are listed only for a media.upload holder" do
    file = Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png")
    as(users(:author)) { Media::Upload.call(file: file) }

    assert_equal %w[media.uploaded], activity(users(:author)).rows.map { |row| row.event.action }
    assert_empty activity(users(:reader)).rows
  end

  test "the same number of queries for 5 and 60 events" do
    counts = [ 5, 60 ].map do |n|
      n.times { |i| as(@me) { create_post(title: "N#{n}-#{i}", published: false) } }
      Current.set(actor: @me, channel: :admin) do
        Dashboard::Activity.new(actor: @me).rows # warm up
        queries = 0
        callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
        ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
          rows = Dashboard::Activity.new(actor: @me).rows
          rows.each { |row| row.record.title }
        end
        queries
      end
    end
    assert_equal counts.first, counts.last
  end

  # --- fix round 1: the read scope is applied in SQL, so the list fills -----

  def blog_reader
    group = AccessControl::Group.create!(name: "Blog readers #{SecureRandom.hex(3)}")
    group.grants.create!(permission: "posts.read", scope: { "content_types" => [ "blog" ] })
    User.create!(email_address: "blog-reader-#{SecureRandom.hex(3)}@example.com", password: "password12345").tap do |user|
      AccessControl::Membership.create!(user:, group:)
    end
  end

  test "an older readable event is listed after 60 newer events on records the viewer can't read" do
    readable = as(@me) { create_post(title: "Readable", published: false) }
    60.times { |i| as(@me) { create_post(title: "Secret #{i}", content_type: "resume_entry", published: false) } }

    assert_equal [ readable ], activity(blog_reader).rows.map(&:record)
  end

  test "an older readable event is listed after 60 uploads for a viewer without media.upload" do
    readable = as(@me) { create_post(title: "Readable", published: false) }
    60.times { as(@me) { Audit.record("media.uploaded", subject: create_media_asset) } }

    assert_equal [ readable ], activity(blog_reader).rows.map(&:record)
    # Sixty uploads fill the read (15 * 4) exactly, so the read cannot tell
    # that the run ends there: it is the only run, kept, and counted as a
    # floor ("60 or more"), never as a number it may not be.
    # The owner's sixty uploads are now one run (the owner's O10), read in
    # one LIMIT of sixty events, so the older post is past the read (Decision
    # 11's cost: a feed whose newest events collapse shows fewer rows).
    rows = activity(@me).rows
    assert_equal [ [ "media.uploaded", 60 ] ], rows.map { |row| [ row.event.action, row.count ] }
    assert_equal "uploaded 60 or more images", rows.first.sentence.parts.map(&:text).join
  end

  test "a run the read cut off says N or more and claims no start" do
    61.times { as(@me) { Audit.record("media.uploaded", subject: create_media_asset) } }
    row = activity.rows.sole
    assert_equal 60, row.count
    assert_equal "uploaded 60 or more images", row.sentence.parts.map(&:text).join
    assert_equal row.event.occurred_at, row.at, "the start is the newest event's own, not the run's"
  end

  test "a complete run beside a cut one reads its exact count and its own start" do
    page = as(@me) { create_page(title: "Whole") }
    start = 1.second.from_now.change(usec: 0)
    add_blocks(page, %w[rich_text] * 3, from: start)
    61.times { travel_to(1.hour.ago) { as(@me) { Audit.record("media.uploaded", subject: create_media_asset) } } }

    rows = activity.rows
    assert_equal [ [ "block.created", 3 ] ], rows.map { |row| [ row.event.action, row.count ] }.select { |a, _| a == "block.created" }
    block_row = rows.find { |row| row.event.action == "block.created" }
    assert_equal "added 3 Rich text blocks to", words(block_row).first
    assert_equal start, block_row.at
    assert_empty rows.select { |row| row.event.action == "media.uploaded" }
  end

  test "a run the read cut off beside another run is not shown" do
    kept = as(@me) { create_post(title: "Kept", published: false) }
    61.times { travel_to(1.hour.ago) { as(@me) { Audit.record("media.uploaded", subject: create_media_asset) } } }
    assert_equal [ kept ], activity.rows.map(&:record), "the last run is cut by the read: dropped, not shown with a false number"
  end

  # --- layout points spec, decision 11: runs ---------------------------------

  def add_blocks(page, types, actor: @me, every: 2.minutes, from: 1.second.from_now.change(usec: 0))
    types.each_with_index.map do |type, index|
      travel_to(from + every * index) { as(actor) { ContentBlocks::Save.call(ContentBlock.new(owner: page, block_type: type)).record } }
    end
  end

  def runs(actor = @me) = activity(actor).rows.select { |row| row.event.action.start_with?("block.", "media.") }.map { |row| [ row.event.action, row.count ] }

  test "four blocks added to one page in a row are one row with their count, its time the first one's and its span the run's" do
    page = as(@me) { create_page(title: "Code block demo") }
    start = 1.second.from_now.change(usec: 0) # after the page's own events: they would split the run
    add_blocks(page, %w[rich_text] * 4, from: start)

    row = activity.rows.find { |r| r.event.action == "block.created" }
    assert_equal [ [ "block.created", 4 ] ], runs
    assert_equal [ "added 4 Rich text blocks to", "Code block demo", "" ], words(row)
    assert_equal page, row.record
    assert_equal start, row.at
    assert_equal start + 6.minutes, row.span_end
  end

  test "blocks of mixed types are counted as blocks" do
    page = as(@me) { create_page(title: "Mixed") }
    add_blocks(page, %w[rich_text post_list rich_text])

    assert_equal [ "added 3 blocks to", "Mixed", "" ], words(activity.rows.find { |r| r.event.action == "block.created" })
  end

  test "a run ends ten minutes after its newest event" do
    page = as(@me) { create_page(title: "Slow") }
    add_blocks(page, %w[rich_text] * 3, every: 5.minutes + 30.seconds)

    assert_equal [ [ "block.created", 2 ], [ "block.created", 1 ] ], runs
  end

  test "a run is broken by another person's event between, by another page and by another action" do
    one = as(@me) { create_page(title: "One") }
    other = as(@me) { create_page(title: "Other") }
    start = 1.second.from_now.change(usec: 0) # after the page's own events: they would split the run
    add_blocks(one, %w[rich_text], from: start)
    add_blocks(one, %w[rich_text], actor: users(:two), from: start + 1.minute)
    add_blocks(one, %w[rich_text], from: start + 2.minutes)
    add_blocks(other, %w[rich_text], from: start + 3.minutes)
    travel_to(start + 4.minutes) { as(@me) { Pages::Save.call(other, translations: { Locales.default => { title: "Other, renamed" } }) } }
    add_blocks(other, %w[rich_text], from: start + 5.minutes)

    assert_equal [ [ "block.created", 1 ] ] * 5, runs
  end

  test "a block deleted from a run is not counted and does not split it" do
    page = as(@me) { create_page(title: "Three") }
    blocks = add_blocks(page, %w[rich_text] * 3)
    as(@me) { ContentBlocks::Destroy.call(blocks.second) }

    assert_equal [ "added 2 Rich text blocks to", "Three", "" ], words(activity.rows.find { |r| r.event.action == "block.created" })
  end

  # The owner's O10: twelve uploads in a row are one row, linked to the library.
  test "uploads in a row are one row, whatever the images, and read uploaded 12 images" do
    12.times { as(@me) { Audit.record("media.uploaded", subject: create_media_asset) } }

    row = activity.rows.first
    assert_equal [ [ "media.uploaded", 12 ] ], runs
    assert_equal [ [ :text, "uploaded " ], [ :collection, "12 images" ] ], row.sentence.parts.map { |part| [ part.kind, part.text ] }
    assert_equal Audit::Sentence.library_route, row.sentence.subject_route
    assert_empty activity(users(:reader)).rows, "a viewer without media.upload sees no upload, counted or not"
  end

  test "an untitled page still names its target in a counted row" do
    page = as(@me) { create_page(title: "Blank soon") }
    page.update_columns(title: {}) # a page whose title is blank in every language
    add_blocks(page, %w[rich_text] * 2)

    assert_equal [ "added 2 Rich text blocks to", "(untitled)", "" ], words(activity.rows.find { |r| r.event.action == "block.created" })
  end

  test "after collapsing there are at most fifteen rows" do
    # Each page's pair at a minute of its own, so no other page's event sits between.
    20.times { |i| add_blocks(as(@me) { create_page(title: "P#{i}") }, %w[rich_text rich_text], every: 1.second, from: (i + 1).minutes.from_now.change(usec: 0)) }

    rows = activity.rows
    assert_equal 15, rows.size
    assert rows.all? { _1.count == 2 }
  end

  test "the same number of statements for a run of 5 blocks and one of 60 (the second read also holds the first's)" do
    counts = [ 5, 60 ].map do |n|
      page = as(@me) { create_page(title: "N#{n}") }
      n.times { as(@me) { Audit.record("block.created", subject: page.content_blocks.create!(block_type: "rich_text", position: 0)) } }
      Current.set(actor: @me, channel: :admin) do
        Dashboard::Activity.new(actor: @me).rows # warm up
        capture_sql { Dashboard::Activity.new(actor: @me).rows.each { |row| row.record.title } }.size
      end
    end
    assert_equal counts.first, counts.last
  end

  test "a block event whose owner the viewer can't read is absent, one on a readable owner is listed" do
    branch = as(@me) { create_page(title: "Branch", published: false) }
    outside = as(@me) { create_page(title: "Outside", published: false) }
    as(@me) { ContentBlocks::Save.call(ContentBlock.new(owner: outside, block_type: "rich_text")) }
    as(@me) { ContentBlocks::Save.call(ContentBlock.new(owner: branch, block_type: "rich_text")) }
    access_control_groups(:branch_editors).grants.create!(permission: "pages.read", scope: { "page_ids" => [ branch.id ] })

    rows = activity(users(:editor_branch)).rows
    assert_equal [ branch ], rows.map(&:record).uniq
    assert rows.any? { |r| r.event.action.start_with?("block.") }
  end

  test "a page outside a branch grant is absent" do
    branch = as(@me) { create_page(title: "Branch", published: false) }
    inside = as(@me) { create_page(title: "Inside", parent: branch, published: false) }
    as(@me) { create_page(title: "Outside", published: false) }
    access_control_groups(:branch_editors).grants.create!(permission: "pages.read", scope: { "page_ids" => [ branch.id ] })

    assert_equal [ branch, inside ].sort_by(&:id), activity(users(:editor_branch)).rows.map(&:record).sort_by(&:id)
  end

  test "a trashed image is absent for a media.upload holder, a kept one listed, and a legacy MediaAsset subject type still counts" do
    kept = create_media_asset
    gone = create_media_asset
    legacy = create_media_asset
    # More than the coalesce window apart, so they are three rows, not a run.
    travel_to(30.minutes.ago) { as(@me) { Audit.record("media.uploaded", subject: kept) } }
    travel_to(15.minutes.ago) { as(@me) { Audit.record("media.uploaded", subject: gone) } }
    Audit::Event.create!(action: "media.uploaded", actor: @me, user_id: @me.id, subject_type: "MediaAsset", subject_id: legacy.id,
      subject_label: "legacy", occurred_at: Time.current, last_occurred_at: Time.current)
    gone.update!(trashed_at: Time.current)

    assert_equal [ kept, legacy ].sort_by(&:id), activity.rows.map(&:record).sort_by(&:id)
  end

  test "an update that only set a future published_at reads as scheduled for that date" do
    post = as(@me) { create_post(title: "Later", published: false) }
    as(@me) { Audit.record("post.updated", subject: post, field_changes: { "published_at" => [ nil, Time.zone.local(2031, 10, 6, 9).iso8601 ] }) }
    row = activity.rows.find { |r| r.event.action == "post.updated" }

    assert_equal [ "scheduled", "Later", " for 6 Oct" ], words(row)
  end

  test "a page scheduled through the Schedule dialog's service reads as scheduled for that date" do
    page = as(@me) { create_page(title: "About", published: false) }
    as(@me) { Pages::Save.call(page, attributes: { published_at: Time.zone.local(2031, 10, 6, 9) }) }
    row = activity.rows.find { |r| r.record == page && r.event.action != "page.created" }

    assert_equal [ "scheduled", "About", " for 6 Oct" ], words(row)
  end

  test "a malformed stored published_at neither raises nor leaves a dangling for" do
    post = as(@me) { create_post(title: "Odd", published: false) }
    as(@me) { Audit.record("post.scheduled", subject: post, field_changes: { "published_at" => [ nil, "not a time" ] }) }
    row = activity.rows.find { |r| r.event.action == "post.scheduled" }

    assert_equal "scheduled", words(row).first
    assert_no_match(/ for\s*\z/, words(row).last)
  end

  test "the feed lists a note started and a note resolved, on a page and on a block, and never a reply" do
    page = create_page(title: "Pricing")
    block = page.content_blocks.create!(block_type: "rich_text", position: 0)
    as(users(:two)) do
      thread = Notes::Start.call(block, body: "A question").record
      Notes::Reply.call(thread, body: "More")
      Notes::Resolve.call(thread)
    end

    rows = Dashboard::Activity.new(actor: users(:one), channel: :admin).rows.select { |row| row.event.action.start_with?("note.") }

    assert_equal %w[note.resolved note.started], rows.map { |row| row.event.action }
    assert_equal [ page, page ], rows.map(&:record) # a block's note is listed under its page
  end
end
