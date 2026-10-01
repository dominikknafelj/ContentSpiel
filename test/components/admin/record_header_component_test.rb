require "test_helper"

# `Admin::RecordHeaderComponent`'s own "Move to trash" gate (Task 10, trash
# spec §4.1): a page with kept subpages is no longer refused -- its whole
# branch moves along with it -- so only the homepage still disables the
# button, and the confirm dialog names how many subpages are coming too.
class Admin::RecordHeaderComponentTest < ViewComponent::TestCase
  include ContentHelper

  test "a page with kept children offers Move to trash, enabled, naming the subpage count" do
    parent = create_page(title: "Section")
    create_page(title: "Child one", parent: parent)
    create_page(title: "Child two", parent: parent)

    render_inline Admin::RecordHeaderComponent.new(page: parent.reload, locale: "en")

    assert_selector "button", text: "Move to trash"
    assert_no_selector "button[disabled]", text: "Move to trash"
    assert_text "This also moves 2 subpages to the trash."
  end

  test "a leaf page's dialog body has no subpage sentence" do
    leaf = create_page(title: "Leaf")

    render_inline Admin::RecordHeaderComponent.new(page: leaf, locale: "en")

    assert_selector "button", text: "Move to trash"
    assert_no_text "subpage"
  end

  test "the homepage's Move to trash stays disabled with the reason, even with kept children" do
    create_page(title: "Child of home", parent: root_page)

    render_inline Admin::RecordHeaderComponent.new(page: root_page.reload, locale: "en")

    assert_selector "button[disabled][title=\"The homepage can't be deleted\"]", text: "Move to trash"
    assert_no_selector "dialog"
  end
end
