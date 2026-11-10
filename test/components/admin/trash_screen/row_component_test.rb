require "test_helper"

# `Admin::TrashScreen::RowComponent`: the parts of a row the integration tests
# don't pin down -- the who/when cell, the delete dialog's subpage count, the
# disabled "Delete now…" with its reason as visible text, and the inline
# "Restore under" for a page that can't go back where it was. (Who is worked out
# by `ListComponent`; a row only shows it.)
class Admin::TrashScreen::RowComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    # Midday, so "In 30 days" can't become 29 on a run that crosses midnight.
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
    assert_selector "[data-retention]", text: "In 30 days"
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
    # The reason, as visible text tied to the controls.
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

  test "the type is the kind's chip and its word, the trasher a small avatar beside the name" do
    users(:two).update!(name: "Ada Lovelace")
    post = create_post(title: "Old post")
    Trash::Move.call(post)

    render_inline row(post.reload, who: "Ada Lovelace", actor: actor(users(:two)))

    type = page.find("td[data-trash-type]")
    assert type.has_selector?("span.inline-flex > span.rounded-chip.size-5[aria-hidden=true] + span.text-small", text: "Post")
    assert_not_includes type[:class].to_s.split, "text-meta"
    trashed = page.find("td[data-trash-who]")
    assert trashed.has_selector?("span.size-\\[22px\\][aria-hidden=true]", text: "AL")
    assert trashed.has_selector?("span.text-ink", text: "Ada Lovelace")
    assert_match(/Ada Lovelace\s*· /, trashed.text)
    assert trashed.has_selector?("time")
    assert_selector "td span.font-medium.text-ink", text: "Old post"
    assert_no_selector "td:first-child .font-semibold"
    assert_selector "button.rounded-button-sm", text: "Restore"

    render_inline row(post.reload, who: "System", actor: actor(nil))
    assert_selector "td[data-trash-who] span.rounded-chip.size-5"
    assert_no_selector "td[data-trash-who] span.size-\\[22px\\]", text: /\w/
  end

  test "an image's thumbnail is 40px on the tile radius" do
    asset = create_media_asset
    Trash::Move.call(asset)

    render_inline row(asset.reload)

    assert_selector "td span.block.size-10.shrink-0.overflow-hidden.rounded-tile.bg-sunken [data-image-empty], td span.block.size-10.rounded-tile img"
    assert_no_selector "td:first-child .size-12"
    assert_no_selector "td:first-child .rounded-cs"
  end

  test "an image row shows a width, the preview or a box, never the original" do
    asset = create_media_asset
    asset.update_columns(width: 1600, height: 1200, preview: nil, renditions: {}) # version: none (a test's own state)
    Trash::Move.call(asset)

    render_inline row(asset.reload, who: "Ada")

    assert_selector "[data-image-empty]"
    assert_no_match %r{/blobs/}, rendered_content
  end

  private

  def row(item, who: "You", actor: actor(users(:one), you: true), retention_days: 30, subpage_sentence: nil, purge_subpage_count: 0, used_by: nil, parent_choices: nil, tab: nil)
    Admin::TrashScreen::RowComponent.new(item:, retention_days:, who:, actor:, subpage_sentence:, purge_subpage_count:, used_by:, parent_choices:, tab:)
  end

  # Who trashed it, as the audit log's actor facts; nil is System.
  def actor(user, you: false)
    Audit::Sentence::Actor.new(you:, user:, user_id: user&.id, via_label: nil, none: false)
  end
end
