require "test_helper"

class Admin::FieldComponentTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "renders a typed input named under the form prefix" do
    field = Field.new(name: "limit", type: :integer, options: { min: 1 })
    render_inline Admin::FieldComponent.new(field:, form_name: "block[settings]", value: 3, locale: "en")
    assert_selector "input[type=number][name='block[settings][limit]'][value='3'][min='1']"
  end

  test "select options are label/value pairs from a {value => label} hash" do
    field = Field.new(name: "role_type", type: :select, options: { options: { "ic" => "Individual contributor" } })
    render_inline Admin::FieldComponent.new(field:, form_name: "post[fields]", value: "ic", locale: "en")
    assert_selector "option[value='ic'][selected]", text: "Individual contributor"
  end

  test "a translated field in another locale shows the read-only original and a translate slot" do
    field = Field.new(name: "headline", type: :string, options: { translated: true })
    render_inline Admin::FieldComponent.new(field:, form_name: "post[fields]", value: nil, original: "Hallo", locale: "en")
    assert_selector "[data-original-for='headline']", text: "Hallo"
    assert_selector "[data-translate-slot='headline']"
  end

  test "errors render under the input" do
    field = Field.new(name: "venue", type: :string, options: { required: true })
    render_inline Admin::FieldComponent.new(field:, form_name: "post[fields]", value: nil, locale: "en", errors: [ "can't be blank" ])
    assert_text "can't be blank"
  end

  test "errors render in an id streams can target" do
    field = Field.new(name: "venue", type: :string, options: {})
    render_inline Admin::FieldComponent.new(field:, form_name: "post[fields]", value: nil, locale: "en", errors: [ "can't be blank" ])
    assert_equal "post_fields-venue-errors", Admin::FieldComponent.error_id("post_fields", "venue")
    assert_selector "#post_fields-venue-errors", text: "can't be blank"
  end

  test "dom_id_prefix turns a bracketed form name into an id-safe prefix" do
    assert_equal "block_settings", Admin::FieldComponent.dom_id_prefix("block[settings]")
    assert_equal "post_fields_speakers_0", Admin::FieldComponent.dom_id_prefix("post[fields][speakers][0]")
  end

  test "an untranslated field in a non-default locale shows the same-in-all-languages hint" do
    field = Field.new(name: "cite", type: :url, options: {})
    render_inline Admin::FieldComponent.new(field:, form_name: "block[settings]", value: nil, locale: "de")
    assert_text "Same in all languages"
  end

  test "no hint for an untranslated field in the default locale" do
    field = Field.new(name: "cite", type: :url, options: {})
    render_inline Admin::FieldComponent.new(field:, form_name: "block[settings]", value: nil, locale: "en")
    refute_text "Same in all languages"
  end

  test "no hint or original for a translated field with no original given" do
    field = Field.new(name: "headline", type: :string, options: { translated: true })
    render_inline Admin::FieldComponent.new(field:, form_name: "post[fields]", value: "Hello", locale: "en")
    refute_text "Same in all languages"
    refute_selector "[data-original-for]"
  end

  test "dispatches every scalar field type without raising" do
    [
      Field.new(name: "a", type: :string, options: {}),
      Field.new(name: "b", type: :text, options: {}),
      Field.new(name: "c", type: :integer, options: {}),
      Field.new(name: "d", type: :boolean, options: {}),
      Field.new(name: "e", type: :date, options: {}),
      Field.new(name: "f", type: :url, options: {}),
      Field.new(name: "g", type: :select, options: { options: %w[x y] }),
      Field.new(name: "h", type: :content_type, options: {}),
      Field.new(name: "i", type: :tag, options: {})
    ].each do |field|
      render_inline Admin::FieldComponent.new(field:, form_name: "post[fields]", value: nil, locale: "en")
      assert_selector "[data-field-name='#{field.name}']"
    end
  end
end

class Admin::FieldComponentTranslationTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "an outdated translated field shows the note beside its original" do
    field = Field.new(name: "headline", type: :string, options: { translated: true })
    render_inline Admin::FieldComponent.new(field:, form_name: "post[fields]", value: "Hallo", original: "Hello!", locale: "de",
      translation_state: :outdated, translation_confirm: { record_type: "Post", record_id: 4, field: "headline", locale: "de" })

    assert_selector "[data-original-for='headline'] ~ #translation-note-post-4-headline button", text: "Mark as up to date"
  end

  test "a view-only outdated field shows the note without a button" do
    field = Field.new(name: "headline", type: :string, options: { translated: true })
    render_inline Admin::FieldComponent.new(field:, form_name: "post[fields]", value: "Hallo", original: "Hello!", locale: "de",
      translation_state: :outdated)

    assert_text "Original changed since this was translated"
    refute_selector "button", text: "Mark as up to date"
  end
end
