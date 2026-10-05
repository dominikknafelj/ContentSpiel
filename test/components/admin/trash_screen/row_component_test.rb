require "test_helper"

# `Admin::TrashScreen::RowComponent` (trash spec §7, round 3): the parts of a
# row the integration tests don't pin down -- the who/when cell, the delete
# dialog's subpage count, the disabled "Delete now…" with its reason as
# visible text, and the inline "Restore under" for a page that can't go back
# where it was. (Who is worked out by `ListComponent`; a row only shows it.)
class Admin::TrashScreen::RowComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    # Midday, so "IN 30 DAYS" can't become 29 on a run that crosses midnight.
    travel_to Time.current.change(hour: 12)
    Current.actor = users(:one)
  end
  teardown { Current.reset }

  test "shows who and when, then the retention tag" do
    post = create_post(title: "Old post")
    Trash::Move.call(post)

    render_inline row(post.reload, who: "Ada Lovelace")

    assert_text "Ada Lovelace"
    assert_selector "time"
    assert_selector "[data-retention]", text: "IN 30 DAYS"
  end

  test "a page row carries its subpage sentence; other rows do not" do
    section = create_page(title: "Section")
    Trash::Move.call(section)

    render_inline row(section.reload, subpage_sentence: "Includes 2 subpages: A, B")
    assert_selector "p", text: "Includes 2 subpages: A, B"

    render_inline row(section.reload)
    assert_no_text "Includes"
  end

  test "a page's delete dialog names how many subpages go with it" do
    section = create_page(title: "Section")
    Trash::Move.call(section)

    render_inline row(section.reload, purge_subpage_count: 1)
    assert_selector "dialog#purge-page-#{section.id}", text: "1 subpage under it is deleted too. This can't be undone."
    assert_selector "dialog#purge-page-#{section.id}", text: "Delete “Section”?"

    render_inline row(section.reload, purge_subpage_count: 0)
    assert_selector "dialog#purge-page-#{section.id}", text: "This can't be undone."
    assert_no_text "subpage"
  end

  test "an image in use has Delete now… disabled, with its reason as visible text and tooltip" do
    asset = create_media_asset
    Trash::Move.call(asset)

    render_inline row(asset.reload, used_by: 2)
    assert_selector "button[disabled][title='Still used by 2 items in the trash']", text: "Delete now…"
    assert_selector "p", text: "Still used by 2 items in the trash"
    assert_selector "button[disabled][aria-describedby='trash-media-#{asset.id}-why']"
    assert_no_selector "dialog"

    render_inline row(asset.reload, used_by: 1)
    assert_selector "p", text: "Still used by 1 item in the trash"

    render_inline row(asset.reload, used_by: nil)
    assert_selector "dialog#purge-media-#{asset.id} h2", text: "Delete “#{asset.title}”?", exact_text: true
    assert_selector "dialog form[action='/cs-studio/trash/media/#{asset.id}'] input[name=_method][value=delete]", visible: :all
  end

  test "a page whose parent is in the trash restores inline, under a chosen parent" do
    section = create_page(title: "Section")
    child = create_page(title: "Child", parent: section)
    Trash::Move.call(child)
    Trash::Move.call(section.reload)

    render_inline row(child.reload, parent_choices: [ [ "Home", root_page.id ] ], tab: "pages")

    assert_selector "form[action='/cs-studio/trash/page/#{child.id}/restore'] label", text: "Restore under"
    assert_selector "form[action='/cs-studio/trash/page/#{child.id}/restore'] select[name=parent_id] option", text: "Home"
    assert_selector "form[action='/cs-studio/trash/page/#{child.id}/restore'] input[name=tab][value=pages]", visible: :all
    assert_selector "form[action='/cs-studio/trash/page/#{child.id}/restore'] button", text: "Restore"
  end

  test "with no parent to offer the inline restore is disabled" do
    section = create_page(title: "Section")
    child = create_page(title: "Child", parent: section)
    Trash::Move.call(child)
    Trash::Move.call(section.reload)

    render_inline row(child.reload, parent_choices: [])

    assert_selector "select[disabled]"
    assert_selector "button[disabled]", text: "Restore"
    # The reason, as visible text tied to the controls (final fix wave, m5).
    assert_selector "p#trash-page-#{child.id}-no-parent", text: "No page you can restore it under."
    assert_selector "select[disabled][aria-describedby='trash-page-#{child.id}-no-parent']"
    assert_selector "button[disabled][aria-describedby='trash-page-#{child.id}-no-parent']", text: "Restore"

    render_inline row(child.reload, parent_choices: [ [ "Home", root_page.id ] ])
    assert_no_text "No page you can restore it under."
  end

  test "a branch root under a kept parent restores in one click" do
    section = create_page(title: "Section")
    Trash::Move.call(section)

    render_inline row(section.reload)

    assert_no_selector "select"
    assert_selector "form[action='/cs-studio/trash/page/#{section.id}/restore'] button", text: "Restore"
  end

  private

  def row(item, who: "You", retention_days: 30, subpage_sentence: nil, purge_subpage_count: 0, used_by: nil, parent_choices: nil, tab: nil)
    Admin::TrashScreen::RowComponent.new(item:, retention_days:, who:, subpage_sentence:, purge_subpage_count:, used_by:, parent_choices:, tab:)
  end
end
