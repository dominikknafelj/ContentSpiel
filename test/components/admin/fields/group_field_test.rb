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

  # `read_field` (Base) has to check the Hash branch before `respond_to?`:
  # `count` is also a `Hash` instance method (returns the number of
  # key/value pairs), so a naive `respond_to?`-first read would silently
  # call that instead of reading the "count" key.
  test "reads a Hash subfield named like a Hash method (count)" do
    FieldGroups.register("test/tally") { |g| g.field :count, :integer }

    field = Field.new(name: "tally", type: :group, options: { of: "test/tally" })
    render_inline Admin::Fields::GroupField.new(field:, form_name: "post[fields]", value: { "count" => 7 }, locale: "en")

    assert_selector "input[name='post[fields][tally][count]'][value='7']"
  ensure
    Rails.application.reloader.prepare!
  end

  test "the group is named by the field's own label where its type gives one, and by its name otherwise" do
    with_test_types do
      render_inline Admin::Fields::GroupField.new(field: Field.new(name: "speaker", type: :group, options: { of: "test/speaker", label: "Main speaker" }), form_name: "post[fields]", value: nil, locale: "en")
      assert_selector "fieldset > legend", exact_text: "Main speaker"

      render_inline Admin::Fields::GroupField.new(field: Field.new(name: "speaker", type: :group, options: { of: "test/speaker" }), form_name: "post[fields]", value: nil, locale: "en")
      assert_selector "fieldset > legend", exact_text: "Speaker"
    end
  end
end
