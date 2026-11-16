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

  test "the list block card says a switched-off filter lists nothing, in the select's description, with the Settings link for settings.manage alone" do
    switch_on_content_types("blog")
    field = Field.new(name: "kind", type: :content_type, options: {})

    as(users(:one)) do
      render_inline Admin::Fields::ContentTypeField.new(field:, form_name: "post[fields]", value: "resume_entry", locale: "en")
    end
    notice = page.find("#post_fields-kind-list-empty")
    assert_equal "This list shows nothing on the site while #{ContentTypes.find('resume_entry').label} is switched off.", notice.text.sub(/\s*Open Post types settings.*/m, "").squish
    assert_nil notice[:role]
    assert_equal "post_fields-kind-list-empty", page.find("select")["aria-describedby"]
    assert_selector "#post_fields-kind-list-empty a[href$='#post_types']", text: "Open Post types settings"

    render_inline Admin::Fields::ContentTypeField.new(field:, form_name: "post[fields]", value: "blog", locale: "en")
    assert_no_selector "[id$=list-empty]"
    assert_nil page.find("select")["aria-describedby"]
  end

  test "someone without settings.manage sees the line and no link" do
    switch_on_content_types("blog")
    field = Field.new(name: "kind", type: :content_type, options: {})

    as(users(:author)) do
      render_inline Admin::Fields::ContentTypeField.new(field:, form_name: "post[fields]", value: "retired_type", locale: "en")
    end
    assert_selector "[id$=list-empty]", text: "while retired_type is switched off"
    assert_no_selector "[id$=list-empty] a"
  end
end
