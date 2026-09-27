require "test_helper"

class Admin::Fields::BooleanFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "renders a checked checkbox plus its hidden unchecked fallback" do
    field = Field.new(name: "featured", type: :boolean, options: {})
    render_inline Admin::Fields::BooleanField.new(field:, form_name: "post[fields]", value: true, locale: "en")

    assert_selector "input[type=checkbox][name='post[fields][featured]'][checked]"
    assert_selector "input[type=hidden][name='post[fields][featured]']", visible: false
  end

  test "unchecked when the value is falsy" do
    field = Field.new(name: "featured", type: :boolean, options: {})
    render_inline Admin::Fields::BooleanField.new(field:, form_name: "post[fields]", value: false, locale: "en")

    refute_selector "input[type=checkbox][checked]"
  end
end
