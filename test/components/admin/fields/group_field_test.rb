require "test_helper"

class Admin::Fields::GroupFieldTest < ViewComponent::TestCase
  include TestTypes
  Field = ContentModel::Definition::Field

  test "renders a nested fieldset naming subfields form_name[field][subfield]" do
    with_test_types do
      field = Field.new(name: "speaker", type: :group, options: { of: "test/speaker" })
      render_inline Admin::Fields::GroupField.new(field:, form_name: "post[fields]", value: { "name" => "Ada" }, locale: "en")

      assert_selector "fieldset input[name='post[fields][speaker][name]'][value='Ada']"
    end
  end

  test "threads a Hash original down to each subfield" do
    with_test_types do
      field = Field.new(name: "speaker", type: :group, options: { of: "test/speaker" })
      render_inline Admin::Fields::GroupField.new(field:, form_name: "post[fields]", value: nil, original: { "name" => "Ada" }, locale: "en")

      assert_selector "[data-original-for='name']", text: "Ada"
    end
  end
end
