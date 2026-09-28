require "test_helper"

class Admin::Fields::ContentTypeFieldTest < ViewComponent::TestCase
  include TestTypes
  Field = ContentModel::Definition::Field

  test "options come from ContentTypes.all, labelled and valued by name" do
    with_test_types do
      field = Field.new(name: "kind", type: :content_type, options: {})
      render_inline Admin::Fields::ContentTypeField.new(field:, form_name: "post[fields]", value: "test/event", locale: "en")

      assert_selector "option[value='test/event'][selected]", text: "Event"
    end
  end
end
