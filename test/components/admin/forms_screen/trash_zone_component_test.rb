require "test_helper"

# The trash confirmation names the pages a form is placed on (design.md
# 2.8): the readable ones by title, the others as a number, each case one
# sentence of its own.
class Admin::FormsScreen::TrashZoneComponentTest < ViewComponent::TestCase
  Placed = Struct.new(:pages, :count_hidden)

  setup { Current.actor = users(:one) }

  def t(key, **values) = I18n.t("admin.components.forms_screen.trash_zone.#{key}", **values)

  def body(pages, hidden)
    render_inline Admin::FormsScreen::TrashZoneComponent.new(form: forms(:contact), placements: Placed.new(pages, hidden))
    page.find("dialog#trash-form-dialog p", match: :first, visible: :all).text
  end

  test "readable pages and pages the viewer can't open are one sentence, with no doubled and" do
    pages = [ create_page(title: "Home"), create_page(title: "Contact us") ]
    text = body(pages, 2)
    assert_includes text, t("placed_with_hidden", count: 2, titles: "Home and Contact us")
    assert_no_match(/and and/, text)
    assert_includes text, t("placed_effect")
  end

  test "only pages the viewer can't open, and only readable ones, each have their sentence" do
    assert_includes body([], 1), t("placed_hidden_only", count: 1)
    assert_includes body([ create_page(title: "Home") ], 0), t("placed", count: 1, titles: "Home")
    assert_includes body([], 0), t("not_placed")
  end
end
