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

  # Final fix wave (P9): a `%>` inside the template's `<%#` comment ended
  # the comment early, and the rest of it rendered as visible text.
  test "the template's own comment never renders" do
    with_test_types do
      field = Field.new(name: "speakers", type: :groups, options: { of: "test/speaker" })
      render_inline Admin::Fields::GroupsField.new(field:, form_name: "post[fields]", value: [], locale: "en")

      assert_not_includes rendered_content, "key at all"
      assert_not_includes rendered_content, "groups_present][]\", since"
    end
  end

  test "an empty groups value renders no existing rows" do
    with_test_types do
      field = Field.new(name: "speakers", type: :groups, options: { of: "test/speaker" })
      render_inline Admin::Fields::GroupsField.new(field:, form_name: "post[fields]", value: nil, locale: "en")

      assert_selector "[data-admin--groups-target='row']", count: 0
    end
  end

  # Design pass round 2 (handoff §9 B23): bordered rows with a handle, an ×
  # that names what it removes, and "+ Add <singular>".
  test "rows have a handle, an x remove button with an accessible name, and a + Add button" do
    with_test_types do
      field = Field.new(name: "speakers", type: :groups, options: { of: "test/speaker" })
      render_inline Admin::Fields::GroupsField.new(field:, form_name: "post[fields]", value: [ { "name" => "Ada" } ], locale: "en")

      singular = FieldGroups.fetch("test/speaker").label.to_s.singularize
      assert_selector "[data-admin--groups-target='row'].border .admin-groups-field__handle"
      assert_selector "[data-admin--groups-target='row'] button[aria-label='Remove #{singular}'][data-action='click->admin--groups#remove']", text: "×"
      assert_selector "button[data-action='click->admin--groups#add']", text: "+ Add #{singular}"
    end
  end
end
