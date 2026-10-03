require "test_helper"

# `Admin::TrashScreen::RowComponent` (trash spec §7): the parts of a row the
# integration tests don't pin down -- the countdown's edges, a trasher who
# isn't known any more, the purge dialog's subpage count, the disabled
# purge for an image still in use, and the parent picker for a page that
# can't go back where it was.
class Admin::TrashScreen::RowComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup { Current.actor = users(:one) }
  teardown { Current.reset }

  test "counts down to the retention job, and says nothing when retention is off" do
    post = create_post(title: "Old post")
    Trash::Move.call(post)
    post.update_columns(trashed_at: 28.days.ago - 1.hour)

    render_inline row(post, retention_days: 30)
    assert_text "Deleted permanently in 2 days"

    render_inline row(post, retention_days: 20)
    assert_text "Deleted permanently today"

    render_inline row(post, retention_days: 0)
    assert_no_text "Deleted permanently in"
    assert_no_text "Deleted permanently today"
  end

  # A nil trasher is either a deleted user or nobody at all (the console,
  # a system job) -- telling the two apart would take the move event, so
  # the row says neither.
  test "names who trashed it, or says it's unknown" do
    post = create_post(title: "Gone post")
    Trash::Move.call(post)

    render_inline row(post.reload)
    assert_text "Trashed by one@example.com"

    post.update_columns(trashed_by_id: nil)
    render_inline row(post.reload)
    assert_text "Trashed by unknown"
    assert_no_text "since left"
  end

  test "a named trasher reads by name, not email" do
    post = create_post(title: "Named trash")
    Trash::Move.call(post)
    users(:one).update!(name: "Ada Lovelace")

    render_inline row(post.reload)

    assert_text "Trashed by Ada Lovelace"
    assert_no_text "one@example.com"
  end

  test "a page's delete dialog names how many subpages go with it" do
    section = create_page(title: "Section")
    Trash::Move.call(section)

    render_inline row(section.reload, purge_subpage_count: 1)
    assert_selector "dialog#purge-page-#{section.id}", text: "1 subpage under it is deleted too. This can't be undone."

    render_inline row(section.reload, purge_subpage_count: 0)
    assert_selector "dialog#purge-page-#{section.id}", text: "This can't be undone."
    assert_no_text "subpage"
  end

  test "an image in use can't be deleted permanently; an unused one opens a confirm dialog" do
    asset = create_media_asset
    Trash::Move.call(asset)

    render_inline row(asset.reload, in_use: true)
    assert_selector "button[disabled][title='Still used by an item in the trash']", text: "Delete permanently"
    assert_no_selector "dialog"

    render_inline row(asset.reload, in_use: false)
    assert_selector "dialog#purge-media-#{asset.id}", text: "Delete permanently?"
    assert_selector "dialog form[action='/cs-studio/trash/media/#{asset.id}'] input[name=_method][value=delete]", visible: :all
  end

  test "a page whose parent is in the trash restores through a parent picker" do
    section = create_page(title: "Section")
    child = create_page(title: "Child", parent: section)
    Trash::Move.call(child)
    Trash::Move.call(section.reload)

    render_inline row(child.reload, parent_choices: [ [ "Home", root_page.id ] ])

    assert_selector "form[action='/cs-studio/trash/page/#{child.id}/restore'] select[name=parent_id] option", text: "Home"
  end

  test "a branch root under a kept parent restores in one click" do
    section = create_page(title: "Section")
    Trash::Move.call(section)

    render_inline row(section.reload, subpages: [])

    assert_no_selector "select"
    assert_selector "form[action='/cs-studio/trash/page/#{section.id}/restore'] button", text: "Restore"
  end

  private

  def row(item, retention_days: 30, subpages: [], purge_subpage_count: 0, in_use: false, parent_choices: nil)
    Admin::TrashScreen::RowComponent.new(item:, retention_days:, subpages:, purge_subpage_count:, in_use:, parent_choices:)
  end
end
