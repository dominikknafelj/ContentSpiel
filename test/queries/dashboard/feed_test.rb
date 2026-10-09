require "test_helper"

# `Dashboard::Feed` is the two personal lists ("Your drafts", "Going live
# next"); the activity feed has its own test (`activity_test.rb`).
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
  end

  test "a page someone else last edited is not my draft" do
    page = Current.set(actor: @me) { create_page(title: "Handed over", published: false) }
    Current.set(actor: @other) { Pages::Save.call(page, translations: { Locales.default => { title: "Taken over" } }) }

    assert_not_includes feed.drafts, page
    assert_includes feed(@other).drafts, page
  end

  test "going live next covers the whole readable site, soonest first, and knows which are mine" do
    soon = Current.set(actor: @other) { create_post(title: "Soon", published: false) }
    soon.update_columns(published_at: 1.day.from_now)
    later = Current.set(actor: @me) { create_post(title: "Later", published: false) }
    later.update_columns(published_at: 3.days.from_now)

    f = feed
    assert_equal [ soon, later ], f.going_live_next.first(2)
    assert_not f.mine?(soon)
    assert f.mine?(later)
    assert feed(@other).mine?(feed(@other).going_live_next.first)
  end

  test "lists are read-scoped and never show trashed records" do
    hidden = Current.set(actor: @me) { create_post(title: "Hidden", published: false) }
    hidden.update_columns(published_at: 1.day.from_now)
    assert_includes feed.going_live_next, hidden
    Current.set(actor: @me) { Trash::Move.call(hidden) }
    assert_not_includes feed.going_live_next, hidden
    assert_not_includes feed.drafts, hidden

    resume = Current.set(actor: @other) { create_post(title: "Resume", content_type: "resume_entry", published: false) }
    resume.update_columns(published_at: 2.days.from_now)
    blog = Current.set(actor: @other) { create_post(title: "Blog", published: false) }
    blog.update_columns(published_at: 2.days.from_now)

    blog_readers = AccessControl::Group.create!(name: "Blog readers")
    blog_readers.grants.create!(permission: "posts.read", scope: { "content_types" => [ "blog" ] })
    reader = User.create!(email_address: "blog-reader@example.com", password: "password12345")
    AccessControl::Membership.create!(user: reader, group: blog_readers)

    assert_includes feed(reader).going_live_next, blog
    assert_not_includes feed(reader).going_live_next, resume
    assert_includes feed(@me).going_live_next, resume
  end

  test "trashed pages are never listed" do
    page = Current.set(actor: @me) { create_page(title: "Binned", published: false) }
    Current.set(actor: @me, channel: :admin) { assert Trash::Move.call(page).ok? }

    assert_not_includes feed.drafts, page
  end

  test "limits apply" do
    8.times { |i| Current.set(actor: @me) { create_post(title: "Draft #{i}", published: false) } }
    8.times { |i| Current.set(actor: @me) { create_post(title: "Later #{i}", published: false).update_columns(published_at: (i + 1).days.from_now) } }
    assert_equal 5, feed.drafts.size
    assert_equal 5, feed.going_live_next.size
  end

  test "constant query count however many records" do
    counts = [ 1, 20 ].map do |n|
      n.times do |i|
        Current.set(actor: @me) do
          create_post(title: "D#{n}-#{i}", published: false)
          create_post(title: "S#{n}-#{i}", published: false).update_columns(published_at: (i + 1).days.from_now)
          create_page(title: "P#{n}-#{i}", published: false)
        end
      end
      f = feed
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("BEGIN", "COMMIT", "SAVEPOINT", "RELEASE") }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        lists = [ f.drafts, f.going_live_next ]
        assert lists.all?(&:any?)
        f.going_live_next.each { |r| f.mine?(r) }
      end
      queries
    end
    assert_equal counts.first, counts.last
  end

  # Final fix wave I1: `ApplicationService#denied` records `access.denied`
  # with the refused record as its subject, and those coalesce -- so a
  # refused attempt must never count as "the newest change".
  test "a refused attempt doesn't take a page or post over" do
    page = Current.set(actor: @me) { create_page(title: "Not yours", published: false) }
    post = Current.set(actor: @me) { create_post(title: "Not yours either", published: false) }
    author = users(:author)
    Current.set(actor: author, channel: :admin) do
      assert Pages::Save.call(page, translations: { Locales.default => { title: "Mine now" } }).denied?
      assert Posts::Save.call(post, translations: { Locales.default => { title: "Mine now" } }).denied?
    end
    assert Audit::Event.exists?(action: "access.denied", subject_type: "Post", subject_id: post.id)

    assert_not_includes feed(author).drafts, page
    assert_not_includes feed(author).drafts, post
    assert_includes feed.drafts, page
    assert_includes feed.drafts, post
  end

  # Final fix wave I3: a block event's subject is the block, but editing a
  # block is editing its page -- so it counts as the page's newest change.
  test "editing a page's block makes the page mine" do
    page = Current.set(actor: @me) { create_page(title: "Blocks", published: false) }
    block = Current.set(actor: @me) { ContentBlocks::Save.call(page.content_blocks.new, attributes: { block_type: "rich_text" }).record }
    travel 1.minute
    Current.set(actor: @other, channel: :admin) do
      result = ContentBlocks::Save.call(block, translations: { Locales.default => { body: rich_text_doc("Edited") } })
      assert result.ok?, result.errors.to_sentence
    end

    assert_includes feed(@other).drafts, page
    assert_not_includes feed.drafts, page
  end

  test "a branch-scoped editor sees only their branch" do
    branch = Current.set(actor: @me) { create_page(title: "Branch", published: false) }
    inside = Current.set(actor: @me) { create_page(title: "Inside", parent: branch, published: false) }
    outside = Current.set(actor: @me) { create_page(title: "Outside", published: false) }
    [ branch, inside, outside ].each { |p| p.update_columns(published_at: 1.day.from_now) }
    access_control_groups(:branch_editors).grants.create!(permission: "pages.read", scope: { "page_ids" => [ branch.id ] })

    f = feed(users(:editor_branch))
    assert_includes f.going_live_next, inside
    assert_includes f.going_live_next, branch
    assert_not_includes f.going_live_next, outside
  end

  test "a note on my draft by someone else does not take it off my drafts, and one by me does not put theirs on mine" do
    mine = as(users(:two)) { create_post(title: "Mine", published: false) }
    theirs = as(users(:one)) { create_post(title: "Theirs", published: false) }
    travel_to(1.minute.from_now) do
      as(users(:one)) { Notes::Start.call(mine, body: "A question") }
      as(users(:two)) { Notes::Start.call(theirs, body: "A question") }
    end

    drafts = Dashboard::Feed.new(actor: users(:two), channel: :admin).drafts

    assert_includes drafts, mine
    assert_not_includes drafts, theirs
  end

  private

  def rich_text_doc(text) = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] } ] }
end
