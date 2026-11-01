require "test_helper"

class Admin::Fields::LinkFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "a text input with inputmode url and the stored address, and no pattern or maxlength" do
    field = Field.new(name: "target", type: :link, options: {})
    render_inline Admin::Fields::LinkField.new(field:, form_name: "block[settings]", value: "/about?x=1", locale: "en")

    assert_selector "input[type=text][inputmode=url][name='block[settings][target]'][value='/about?x=1']"
    assert_no_selector "input[pattern]"
    assert_no_selector "input[maxlength]"
  end
end
