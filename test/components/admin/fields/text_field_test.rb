require "test_helper"

class Admin::Fields::TextFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "renders a textarea named and valued" do
    field = Field.new(name: "excerpt", type: :text, options: {})
    render_inline Admin::Fields::TextField.new(field:, form_name: "post[fields]", value: "A longer block of text.", locale: "en")

    assert_selector "textarea[name='post[fields][excerpt]']", text: "A longer block of text."
  end

  test "a field with a help line is described by it, and one without is described by nothing" do
    field = Field.new(name: "description", type: :text, options: { help: "Describe it." })
    render_inline Admin::Fields::TextField.new(field:, form_name: "block[settings]", value: nil, locale: "en", id_prefix: "block-7")
    assert_selector "textarea#block-7-description[aria-describedby='block-7-description-help']"

    render_inline Admin::Fields::TextField.new(field: Field.new(name: "excerpt", type: :text, options: {}), form_name: "post[fields]", value: nil, locale: "en")
    assert_no_selector "textarea[aria-describedby]"
  end
end
