require "test_helper"

# A field of the builder: a paper row on the tile radius with no shadow,
# its head unruled, Required in the label's size, and up and down as icon
# buttons whose one name is their label.
class Admin::FormsScreen::FieldRowComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }

  def t(key, **values) = I18n.t("admin.components.forms_screen.field_row.#{key}", **values)

  def render_row(errors: [])
    row = Admin::FormsScreen::Draft.from_form(forms(:contact)).rows.second
    render_inline Admin::FormsScreen::FieldRowComponent.new(row: row, locale: "en", structure: true, first: false, last: false, errors: errors)
    row
  end

  test "a field is a paper row on the tile radius; up and down are icon buttons named by their labels" do
    row = render_row
    label = row.label["en"]

    assert_selector "div.admin-form-field-row.rounded-tile.bg-paper"
    assert_no_selector ".admin-form-field-row[class*='shadow-']"
    head = page.find(".admin-form-field-row > div", match: :first)
    assert_not head[:class].split.include?("border-b"), "the head is not ruled off from the body"
    assert head.has_selector?("span.text-label.text-meta", text: t("required"), visible: :all)
    assert head.has_selector?("span", text: Forms::FieldTypes.find(row.type).label)

    %w[up down].each do |direction|
      button = head.find("button[data-admin--forms--builder-target=#{direction}]")
      assert_equal t(direction, label: label), button["aria-label"]
      assert button.has_css?("svg"), "#{direction} draws its icon"
      assert_equal t(direction, label: label), button.find("[data-tooltip]", visible: :all).text(:all).strip, "the tooltip says the name"
      assert_not_includes button.text(:all), "↑"
      assert_not_includes button.text(:all), "↓"
    end
    assert head.has_button?(t("remove"))
  end

  test "an invalid label is aria-invalid with the shared edge, never a danger border" do
    render_row(errors: [ "Give it a label." ])

    assert_selector ".admin-field > input[aria-invalid=true][name$='[label][en]']"
    assert_selector ".admin-field > [id$='-errors'] > p", text: "Give it a label."
    assert_no_match(/!border-danger/, page.native.to_html)
  end
end
