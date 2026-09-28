require "test_helper"

class Admin::Fields::TextFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "renders a textarea named and valued" do
    field = Field.new(name: "excerpt", type: :text, options: {})
    render_inline Admin::Fields::TextField.new(field:, form_name: "post[fields]", value: "A longer block of text.", locale: "en")

    assert_selector "textarea[name='post[fields][excerpt]']", text: "A longer block of text."
  end
end
