require "test_helper"

class Admin::Fields::DateFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "renders a date input with an ISO value" do
    field = Field.new(name: "starts_on", type: :date, options: {})
    render_inline Admin::Fields::DateField.new(field:, form_name: "post[fields]", value: Date.new(2026, 10, 1), locale: "en")

    assert_selector "input[type=date][name='post[fields][starts_on]'][value='2026-10-01']"
  end

  test "a blank value renders no value attribute" do
    field = Field.new(name: "starts_on", type: :date, options: {})
    render_inline Admin::Fields::DateField.new(field:, form_name: "post[fields]", value: nil, locale: "en")

    assert_selector "input[type=date][name='post[fields][starts_on]']"
  end
end
