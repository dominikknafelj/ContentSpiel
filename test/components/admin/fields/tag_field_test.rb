require "test_helper"

class Admin::Fields::TagFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "renders a text input with a datalist of existing tag names for autocomplete" do
    tag = Tag.create!(name: "conference")
    field = Field.new(name: "topic", type: :tag, options: {})
    render_inline Admin::Fields::TagField.new(field:, form_name: "post[fields]", value: tag.name, locale: "en")

    assert_selector "input[type=text][name='post[fields][topic]'][value='conference']"
    assert_selector "datalist option[value='conference']"
  end
end
