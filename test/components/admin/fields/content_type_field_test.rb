require "test_helper"

class Admin::Fields::ContentTypeFieldTest < ViewComponent::TestCase
  include TestTypes
  Field = ContentModel::Definition::Field

  test "the select offers the switched-on types and keeps a stored switched-off value, marked" do
    switch_on_content_types("blog", "now_update")
    field = Field.new(name: "kind", type: :content_type, options: {})

    render_inline Admin::Fields::ContentTypeField.new(field:, form_name: "post[fields]", value: "blog", locale: "en")
    assert_equal %w[blog now_update], page.all("option").map(&:value).reject(&:empty?)
    assert_no_text "switched off"

    render_inline Admin::Fields::ContentTypeField.new(field:, form_name: "post[fields]", value: "resume_entry", locale: "en")
    assert_equal %w[blog now_update resume_entry], page.all("option").map(&:value).reject(&:empty?)
    assert_selector "option[value=resume_entry][selected]", text: "#{ContentTypes.find('resume_entry').label} (switched off)"
  end

  test "options come from ContentTypes.all, labelled and valued by name" do
    with_test_types do
      field = Field.new(name: "kind", type: :content_type, options: {})
      render_inline Admin::Fields::ContentTypeField.new(field:, form_name: "post[fields]", value: "test/event", locale: "en")

      assert_selector "option[value='test/event'][selected]", text: "Event"
    end
  end
end
