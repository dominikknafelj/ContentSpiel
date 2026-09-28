require "test_helper"

class Admin::Fields::GroupsFieldTest < ViewComponent::TestCase
  include TestTypes
  Field = ContentModel::Definition::Field

  test "renders one row per existing value, named form_name[field][index][subfield]" do
    with_test_types do
      field = Field.new(name: "speakers", type: :groups, options: { of: "test/speaker" })
      value = [ { "name" => "Ada" }, { "name" => "Grace" } ]
      render_inline Admin::Fields::GroupsField.new(field:, form_name: "post[fields]", value: value, locale: "en")

      assert_selector "input[name='post[fields][speakers][0][name]'][value='Ada']"
      assert_selector "input[name='post[fields][speakers][1][name]'][value='Grace']"
    end
  end

  test "renders a <template> for new rows, and add/remove controls wired to admin--groups" do
    with_test_types do
      field = Field.new(name: "speakers", type: :groups, options: { of: "test/speaker" })
      render_inline Admin::Fields::GroupsField.new(field:, form_name: "post[fields]", value: [], locale: "en")

      assert_selector "[data-controller='admin--groups']"
      assert_selector "template[data-admin--groups-target='template']", visible: false
      # Capybara deliberately empties a <template>'s content when building its
      # queryable DOM (Capybara.HTML, matching real browser semantics where a
      # template's content isn't part of the document) -- so the placeholder
      # row inside it can only be checked against the raw rendered string.
      assert_includes rendered_content, "post[fields][speakers][__INDEX__][name]"
      assert_selector "[data-action='click->admin--groups#add']"
    end
  end

  test "an empty groups value renders no existing rows" do
    with_test_types do
      field = Field.new(name: "speakers", type: :groups, options: { of: "test/speaker" })
      render_inline Admin::Fields::GroupsField.new(field:, form_name: "post[fields]", value: nil, locale: "en")

      assert_selector "[data-admin--groups-target='row']", count: 0
    end
  end
end
