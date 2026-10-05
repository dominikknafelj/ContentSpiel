require "test_helper"

# `Admin::TrashScreen::ListComponent` (trash spec §7, round 3): what the list
# works out ONCE for the whole page and hands to its rows -- who trashed each
# item, a branch root's subpage sentence and purge count, an image's "still
# used by", the parent choices -- and the three empty states. The rows' own
# markup is `RowComponentTest`'s; the screen as a whole is the integration
# tests'.
class Admin::TrashScreen::ListComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    travel_to Time.current.change(hour: 12)
    Current.actor = users(:one)
    Current.channel = :admin
  end
  teardown { Current.reset }

  def list(items, **options)
    render_inline Admin::TrashScreen::ListComponent.new(items:, retention_days: 30, **options)
  end

  def trash(record, as: users(:one))
    Current.actor = as
    assert Trash::Move.call(record).ok?
    Current.actor = users(:one)
    record.reload
  end

  test "an empty list is the empty state for its tab, inside the card" do
    list([])
    assert_selector "div.rounded-cs.border", text: "The trash is empty"
    assert_text "Deleted pages, posts and images show up here until they're deleted for good."
    assert_no_selector "table"

    { "pages" => "No pages in the trash", "posts" => "No posts in the trash", "images" => "No images in the trash" }.each do |tab, title|
      list([], tab:)
      assert_text title
    end
  end

  test "a list that is empty only for this viewer says so instead of claiming the trash is empty" do
    list([], tab: "posts", hidden_items: true)

    assert_text "Nothing here you can restore."
    assert_text "The trash holds items you can't restore or delete one by one. Empty trash deletes them."
    assert_no_text "No posts in the trash"
    assert_no_text "The trash is empty"
  end

  test "one row per item under the five headings, and the footer slot inside the card" do
    post = trash(create_post(title: "Old post"))
    asset = trash(create_media_asset)

    render_inline(Admin::TrashScreen::ListComponent.new(items: [ post, asset ], retention_days: 30)) { |c| c.with_footer { "PAGE FOOTER" } }

    assert_equal [ "Item", "Type", "Trashed", "Deletes", "Actions" ], page.all("thead th").map { |th| th.text.strip }
    assert_selector "tbody tr", count: 2
    assert_selector "tbody tr#trash-post-#{post.id}"
    assert_selector "tbody tr#trash-media-#{asset.id}"
    assert_selector "div.rounded-cs.border", text: "PAGE FOOTER"
  end

  test "who: You for the viewer's own trashing, the name for someone else's, System when nobody is recorded" do
    mine = trash(create_post(title: "Mine"))
    users(:two).update!(name: "Ada Lovelace")
    theirs = trash(create_post(title: "Theirs"), as: users(:two))
    nobody = create_post(title: "Nobody's")
    nobody.update_columns(trashed_at: Time.current)

    list([ mine, theirs, nobody.reload ])

    assert_selector "#trash-post-#{mine.id}", text: "You"
    assert_selector "#trash-post-#{theirs.id}", text: "Ada Lovelace"
    assert_no_selector "#trash-post-#{theirs.id}", text: "You"
    assert_selector "#trash-post-#{nobody.id}", text: "System"
  end

  test "who: a user deleted since is read from the trashing's own event, never passed off as System" do
    gone = User.create!(email_address: "gone@example.com", password: "a much Longer passw0rd")
    membership = AccessControl::Membership.create!(user: gone, group: access_control_groups(:admin))
    post = trash(create_post(title: "Orphaned"), as: gone)
    assert_equal gone.id, post.trashed_by_id
    membership.delete
    User.where(id: gone.id).delete_all # the FK nullifies `trashed_by_id`; the event keeps the id

    list([ post.reload ])

    assert_nil post.trashed_by_id
    assert_selector "#trash-post-#{post.id}", text: "a deleted user"
    assert_no_selector "#trash-post-#{post.id}", text: "System"
  end

  test "who: a trashing made through a token names the token, with the audit log's comma" do
    post = create_post(title: "By token")
    token, = ApiToken.generate!(users(:one), name: "claude-desktop")
    Current.actor = token
    Current.channel = :mcp
    assert Trash::Move.call(post).ok?
    Current.actor = users(:one)
    Current.channel = :admin

    list([ post.reload ])

    assert_selector "#trash-post-#{post.id}", text: "You, via claude-desktop"
  end

  test "a branch root's sentence counts every member and names at most three; its purge dialog counts every descendant" do
    section = create_page(title: "Section")
    %w[Alpha Beta Gamma Delta].each { |title| create_page(title:, parent: section) }
    section = trash(section)

    list([ section ])

    assert_selector "#trash-page-#{section.id}", text: "Includes 4 subpages: Alpha, Beta, Gamma and 1 more"
    assert_selector "dialog#purge-page-#{section.id}", text: "4 subpages under it are deleted too."
    # One row: the members have none of their own.
    assert_selector "tbody tr", count: 1
  end

  test "an image something in the trash still uses can't be deleted yet, and counts a page once however it uses the image" do
    asset = create_media_asset
    owner = create_page(title: "Owner")
    assert Pages::Save.call(owner, attributes: { hero_media_asset_id: asset.id }).ok?
    trash(owner)
    asset = trash(asset)
    free = trash(create_media_asset)

    list([ asset, free ])

    assert_selector "#trash-media-#{asset.id} button[disabled]", text: "Delete now…"
    assert_selector "#trash-media-#{asset.id}", text: "Still used by 1 item in the trash"
    assert_no_selector "#trash-media-#{free.id} button[disabled]"
    assert_no_selector "#trash-media-#{free.id}", text: "Still used"
  end

  test "a page whose parent is in the trash gets Restore under with the pages the viewer may create under, by path" do
    section = create_page(title: "Section")
    child = create_page(title: "Child", parent: section)
    child = trash(child)
    trash(section.reload)
    about = create_page(title: "About")
    create_page(title: "Team", parent: about)

    list([ child.reload ], tab: "pages")

    options = page.all("#trash-page-#{child.id} select[name=parent_id] option").map(&:text)
    assert_includes options, "#{root_page.title} / About / Team"
    assert_includes options, "#{root_page.title} / About"
    assert_not(options.any? { |label| label.include?("Section") }, "a trashed page is no parent")
    assert_selector "#trash-page-#{child.id} input[name=tab][value=pages]", visible: :all
  end

  # Loaded the way `Admin::TrashController#index` loads its rows: `trashed_by`
  # preloaded (the list reads it for every row; that preload is the caller's).
  test "the lookups don't grow with the rows" do
    ids = Array.new(6) { |index| trash(create_post(title: "Post #{index}")).id }
    load = ->(count) { Post.where(id: ids.first(count)).includes(:trashed_by).to_a }
    two = load.call(2)
    six = load.call(6)

    few = count_queries { list(two) }
    many = count_queries { list(six) }

    assert_equal few, many, "the list asked more queries for six rows than for two"
    assert_operator few, :>=, 1
  end

  private

  def count_queries
    count = 0
    # Cached answers count too: the test runs inside the executor, so a repeated query comes from the query cache.
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end
end
