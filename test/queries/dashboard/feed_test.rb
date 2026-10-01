require "test_helper"

class Dashboard::FeedTest < ActiveSupport::TestCase
  setup { @me = users(:one); @other = users(:two) }

  def feed(actor = @me) = Current.set(actor:, channel: :admin) { Dashboard::Feed.new(actor:) }

  test "drafts are my unpublished pages and posts, newest change first" do
    mine = Current.set(actor: @me) { create_post(title: "Mine", published: false) }
    theirs = Current.set(actor: @other) { create_post(title: "Theirs", published: false) }
    theirs.update_columns(author_id: @other.id)
    page = Current.set(actor: @me) { create_page(title: "My draft page", published: false) }

    assert_equal [ page, mine ], feed.drafts
  end

  test "a post I authored stays mine after someone else edits it" do
    post = Current.set(actor: @me) { create_post(title: "Authored", published: false) }
    post.update_columns(author_id: @me.id)
    Current.set(actor: @other) { Posts::Save.call(post, translations: { Locales.default => { title: "Authored!" } }) }

    assert_includes feed.drafts, post
    assert_not_includes feed.recently_edited, post
  end

  test "a page someone else edited after me leaves my recently edited but stays in recently updated" do
    page = Current.set(actor: @me) { create_page(title: "Shared") }
    assert_includes feed.recently_edited, page

    Current.set(actor: @other) { Pages::Save.call(page, translations: { Locales.default => { title: "Shared!" } }) }

    assert_not_includes feed.recently_edited, page
    assert_includes feed.recently_updated, page
    assert_equal @other, feed.last_change(page)[:actor]
    assert_includes feed(@other).recently_edited, page
  end

  test "a page someone else last edited is not my draft" do
    page = Current.set(actor: @me) { create_page(title: "Handed over", published: false) }
    Current.set(actor: @other) { Pages::Save.call(page, translations: { Locales.default => { title: "Taken over" } }) }

    assert_not_includes feed.drafts, page
    assert_includes feed(@other).drafts, page
  end

  test "scheduled lists are ordered soonest first; going live next covers the whole readable site" do
    soon = Current.set(actor: @other) { create_post(title: "Soon", published: false) }
    soon.update_columns(published_at: 1.day.from_now)
    later = Current.set(actor: @me) { create_post(title: "Later", published: false) }
    later.update_columns(published_at: 3.days.from_now)

    assert_equal [ later ], feed.scheduled
    assert_equal [ soon, later ], feed.going_live_next.first(2)
  end

  test "lists are read-scoped and never show trashed records" do
    hidden = Current.set(actor: @me) { create_post(title: "Hidden", published: false) }
    Current.set(actor: @me) { Trash::Move.call(hidden) }
    assert_not_includes feed.recently_updated, hidden
    assert_not_includes feed.drafts, hidden
    assert_not_includes feed.recently_edited, hidden

    resume = Current.set(actor: @other) { create_post(title: "Resume", content_type: "resume_entry", published: false) }
    resume.update_columns(published_at: 2.days.from_now)
    blog = Current.set(actor: @other) { create_post(title: "Blog", published: false) }
    blog.update_columns(published_at: 2.days.from_now)

    blog_readers = AccessControl::Group.create!(name: "Blog readers")
    blog_readers.grants.create!(permission: "posts.read", scope: { "content_types" => [ "blog" ] })
    reader = User.create!(email_address: "blog-reader@example.com", password: "password123")
    AccessControl::Membership.create!(user: reader, group: blog_readers)

    assert_includes feed(reader).going_live_next, blog
    assert_not_includes feed(reader).going_live_next, resume
    assert_not_includes feed(reader).recently_updated, resume
    assert_includes feed(@me).going_live_next, resume
  end

  test "images are listed only for a media.upload holder" do
    file = Rack::Test::UploadedFile.new(file_fixture("tiny.png"), "image/png")
    asset = Current.set(actor: users(:author), channel: :admin) { Media::Upload.call(file: file).record }
    assert asset.persisted?

    author_feed = feed(users(:author))
    assert_includes author_feed.recently_updated, asset
    assert_includes author_feed.recently_edited, asset
    assert_equal users(:author), author_feed.last_change(asset)[:actor]

    assert_not_includes feed(users(:reader)).recently_updated, asset
  end

  test "an image event recorded under the legacy MediaAsset subject type still counts" do
    asset = create_media_asset
    Audit::Event.create!(action: "media.uploaded", actor: @me, user_id: @me.id, subject_type: "MediaAsset", subject_id: asset.id,
      subject_label: "tiny.png", occurred_at: Time.current, last_occurred_at: Time.current)

    assert_includes feed.recently_edited, asset
    assert_equal @me, feed.last_change(asset)[:actor]
  end

  test "a system change reads as no actor; a record with no event has no last change" do
    post = Current.set(actor: @me) { create_post(title: "Touched by the system") }
    Current.set(actor: nil, channel: :system) { Posts::Save.call(post, translations: { Locales.default => { title: "Cleaned up" } }) }

    change = feed.last_change(post)
    assert_not_nil change
    assert_nil change[:actor]
    assert_in_delta Time.current, change[:at], 1.minute

    # Saved straight through the model, as `create_media_asset` does: no
    # service, so no audit event at all.
    unaudited = create_media_asset
    assert_not Audit::Event.exists?(subject_id: unaudited.id, subject_type: [ "Media::Asset", "MediaAsset" ])

    f = feed
    assert_includes f.recently_updated, unaudited
    assert_nil f.last_change(unaudited)
  end

  test "limits apply" do
    16.times { |i| Current.set(actor: @me) { create_post(title: "Draft #{i}", published: false) } }
    assert_equal 10, feed.drafts.size
    assert_equal 10, feed.recently_edited.size
    assert_equal 15, feed.recently_updated.size
  end

  # A change made through an API token (MCP) is the token's user's change:
  # the event's actor is the token, its `user_id` the human behind it, and
  # both come back preloaded, so the dashboard can say "by <user>" without
  # a query per row (the constant-query tests here and in the dashboard's
  # integration test pin that part).
  test "a change made through an API token carries its user" do
    post = Current.set(actor: @me) { create_post(title: "Via MCP") }
    token, = ApiToken.generate!(@other, group: access_control_groups(:admin))
    Current.set(actor: token, channel: :mcp) { Posts::Save.call(post, translations: { Locales.default => { title: "Via MCP!" } }) }

    f = feed
    f.recently_updated
    change = f.last_change(post)
    assert_equal token, change[:actor]
    assert_equal @other, change[:user]
  end

  test "constant query count however many records" do
    counts = [ 1, 20 ].map do |n|
      n.times do |i|
        Current.set(actor: @me) do
          create_post(title: "D#{n}-#{i}", published: false)
          create_post(title: "S#{n}-#{i}", published: false).update_columns(published_at: (i + 1).days.from_now)
          create_page(title: "P#{n}-#{i}", published: false)
          create_media_asset.tap { |asset| Audit.record("media.uploaded", subject: asset) }
        end
      end
      f = feed
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("BEGIN", "COMMIT", "SAVEPOINT", "RELEASE") }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        lists = [ f.drafts, f.scheduled, f.recently_edited, f.going_live_next, f.recently_updated ]
        assert lists.all?(&:any?)
        lists.flatten.each { |r| f.last_change(r) }
      end
      queries
    end
    assert_equal counts.first, counts.last
  end
end
