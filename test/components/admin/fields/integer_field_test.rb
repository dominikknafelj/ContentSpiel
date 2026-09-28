require "test_helper"

class Admin::Fields::IntegerFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "renders a number input with min and max" do
    field = Field.new(name: "limit", type: :integer, options: { min: 1, max: 10 })
    render_inline Admin::Fields::IntegerField.new(field:, form_name: "block[settings]", value: 3, locale: "en")

    assert_selector "input[type=number][name='block[settings][limit]'][value='3'][min='1'][max='10']"
  end

  test "no min/max attributes when the field declares none" do
    field = Field.new(name: "limit", type: :integer, options: {})
    render_inline Admin::Fields::IntegerField.new(field:, form_name: "block[settings]", value: nil, locale: "en")

    refute_selector "input[min]"
    refute_selector "input[max]"
  end
end
