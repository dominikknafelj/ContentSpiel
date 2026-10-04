require "test_helper"

class Admin::Fields::DateFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "renders a date input with an ISO value" do
    field = Field.new(name: "starts_on", type: :date, options: {})
    render_inline Admin::Fields::DateField.new(field:, form_name: "post[fields]", value: Date.new(2026, 10, 1), locale: "en")

    assert_selector "input[type=text][name='post[fields][starts_on]'][value='2026-10-01']"
  end

  test "a blank value renders no value attribute" do
    field = Field.new(name: "starts_on", type: :date, options: {})
    render_inline Admin::Fields::DateField.new(field:, form_name: "post[fields]", value: nil, locale: "en")

    assert_selector "input[type=text][name='post[fields][starts_on]']"
  end

  # Design pass round 2 (handoff §9 B23): a mono yyyy-mm-dd text input, still
  # submitted as the same param -- no browser date picker.
  test "is a mono text input with a strict pattern and placeholder" do
    field = Field.new(name: "starts_on", type: :date, options: {})
    render_inline Admin::Fields::DateField.new(field:, form_name: "post[fields]", value: "2024-01-01", locale: "en")

    assert_selector "input[type=text][pattern][placeholder='yyyy-mm-dd'][inputmode=numeric][value='2024-01-01'].font-cs-mono"
  end
end
