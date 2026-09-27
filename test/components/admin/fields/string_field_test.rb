require "test_helper"

class Admin::Fields::StringFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "renders a text input named and valued" do
    field = Field.new(name: "title", type: :string, options: {})
    render_inline Admin::Fields::StringField.new(field:, form_name: "post[fields]", value: "Hello", locale: "en")

    assert_selector "input[type=text][name='post[fields][title]'][value='Hello']"
  end

  test "a required field renders the required attribute" do
    field = Field.new(name: "title", type: :string, options: { required: true })
    render_inline Admin::Fields::StringField.new(field:, form_name: "post[fields]", value: nil, locale: "en")

    assert_selector "input[required]"
  end
end
