require "test_helper"

class Dashboard::ActivityTest < ActiveSupport::TestCase
  setup { @me = users(:one) }

  def activity(actor = @me, limit: 15) = Current.set(actor:, channel: :admin) { Dashboard::Activity.new(actor:, limit:) }

  def sentences(actor = @me)
    activity(actor).rows.map { |row| [ row.actor_name, row.sentence_parts[0], row.record.title, row.sentence_parts[2] ] }
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

    assert_includes sentences, [ "#{@me.display_name}", "published", "Hello", "" ]
    assert_includes sentences, [ @me.display_name, "scheduled", "Hello", " for 6 Oct" ]
    assert_includes sentences, [ @me.display_name, "created", "Hello", "" ]
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
    assert_equal "moved", activity.rows.second.sentence_parts[0]
    assert_equal " to the trash", activity.rows.second.sentence_parts[2]
  end

  test "a block edit reads as editing the page and points at the page" do
    page = as(@me) { create_page(title: "About") }
    block = as(@me) { ContentBlocks::Save.call(ContentBlock.new(owner: page, block_type: "rich_text")).record }
    row = activity.rows.find { |r| r.event.action.start_with?("block.") }

    assert_equal "edited a block on", row.sentence_parts[0]
    assert_equal page, row.record
    assert block.persisted?
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

    names = activity.rows.to_h { |row| [ row.record.title, row.actor_name ] }
    assert_equal "System", names["By the system"]
    assert_equal "a deleted user", names["By a ghost"]
  end

  test "a change through an API token is the user's, flagged via_token, and never names the token" do
    token, = ApiToken.generate!(@me, group: access_control_groups(:admin))
    as(token, channel: :mcp) { create_post(title: "Via MCP", published: false) }
    row = activity.rows.first

    assert row.via_token
    assert_equal @me.display_name, row.actor_name
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
end
