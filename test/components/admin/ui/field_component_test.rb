require "test_helper"

class Admin::Ui::FieldComponentTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "renders a typed input named under the form prefix" do
    field = Field.new(name: "limit", type: :integer, options: { min: 1 })
    render_inline Admin::Ui::FieldComponent.new(field:, form_name: "block[settings]", value: 3, locale: "en")
    assert_selector "input[type=number][name='block[settings][limit]'][value='3'][min='1']"
  end

  test "select options are label/value pairs from a {value => label} hash" do
    field = Field.new(name: "role_type", type: :select, options: { options: { "ic" => "Individual contributor" } })
    render_inline Admin::Ui::FieldComponent.new(field:, form_name: "post[fields]", value: "ic", locale: "en")
    assert_selector "option[value='ic'][selected]", text: "Individual contributor"
  end

  test "a translated field in another locale shows the read-only original and a translate slot" do
    field = Field.new(name: "headline", type: :string, options: { translated: true })
    render_inline Admin::Ui::FieldComponent.new(field:, form_name: "post[fields]", value: nil, original: "Hallo", locale: "en")
    assert_selector "[data-original-for='headline']", text: "Hallo"
    assert_selector "[data-translate-slot='headline']"
  end

  test "errors render under the input" do
    field = Field.new(name: "venue", type: :string, options: { required: true })
    render_inline Admin::Ui::FieldComponent.new(field:, form_name: "post[fields]", value: nil, locale: "en", errors: [ "can't be blank" ])
    assert_text "can't be blank"
  end

  test "errors render in an id streams can target" do
    field = Field.new(name: "venue", type: :string, options: {})
    render_inline Admin::Ui::FieldComponent.new(field:, form_name: "post[fields]", value: nil, locale: "en", errors: [ "can't be blank" ])
    assert_equal "post_fields-venue-errors", Admin::Ui::FieldComponent.error_id("post_fields", "venue")
    assert_selector "#post_fields-venue-errors", text: "can't be blank"
  end

  test "dom_id_prefix turns a bracketed form name into an id-safe prefix" do
    assert_equal "block_settings", Admin::Ui::FieldComponent.dom_id_prefix("block[settings]")
    assert_equal "post_fields_speakers_0", Admin::Ui::FieldComponent.dom_id_prefix("post[fields][speakers][0]")
  end

  test "no original for a translated field with no original given" do
    field = Field.new(name: "headline", type: :string, options: { translated: true })
    render_inline Admin::Ui::FieldComponent.new(field:, form_name: "post[fields]", value: "Hello", locale: "en")
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
      Field.new(name: "i", type: :tag, options: {}),
      Field.new(name: "j", type: :code, options: {})
    ].each do |field|
      render_inline Admin::Ui::FieldComponent.new(field:, form_name: "post[fields]", value: nil, locale: "en")
      assert_selector "[data-field-name='#{field.name}']"
    end
  end

  test "a code field is never offered to the AI translation" do
    assert_not_includes Admin::Ui::FieldComponent::TRANSLATABLE_TYPES, :code
  end
end

class Admin::Ui::FieldComponentTranslationTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "an outdated translated field shows the changed card beside its original" do
    field = Field.new(name: "headline", type: :string, options: { translated: true })
    render_inline Admin::Ui::FieldComponent.new(field:, form_name: "post[fields]", value: "Hallo", original: "Hello!", locale: "de",
      translation_state: :outdated, translation_confirm: { record_type: "Post", record_id: 4, field: "headline", locale: "de" })

    assert_selector "[data-original-for='headline'] button[form='translation-confirm-form']", text: "Still correct — mark up to date"
  end

  test "a view-only outdated field shows the note without a button" do
    field = Field.new(name: "headline", type: :string, options: { translated: true })
    render_inline Admin::Ui::FieldComponent.new(field:, form_name: "post[fields]", value: "Hallo", original: "Hello!", locale: "de",
      translation_state: :outdated)

    assert_text "English changed since this was translated."
    refute_selector "button", text: "Still correct — mark up to date"
  end

  # Design answer C5 (`label:` on a schema field).
  test "the label is the field's own where its type gives one, and its name humanised otherwise" do
    render_inline Admin::Ui::FieldComponent.new(field: Field.new(name: "filename", type: :string, options: { label: "File name" }), form_name: "block[settings]", value: nil, locale: "en")
    assert_selector "label[for='block_settings-filename']", exact_text: "File name"

    render_inline Admin::Ui::FieldComponent.new(field: Field.new(name: "role_type", type: :string, options: {}), form_name: "block[settings]", value: nil, locale: "en")
    assert_selector "label[for='block_settings-role_type']", exact_text: "Role type"
  end

  # The segmented control names itself with its legend; a <label for> above
  # it would point at no control (the radios have ids of their own).
  test "a segmented select has its legend and no label of the field's above it, and its error slot is where it always is" do
    field = Field.new(name: "kind", type: :select, options: { options: { "note" => "Note" }, control: :segmented })
    render_inline Admin::Ui::FieldComponent.new(field:, form_name: "block[settings]", value: "note", locale: "en", id_prefix: "block-7", errors: [ "is not included in the list" ])

    assert_no_selector "label[for='block-7-kind']"
    assert_selector "fieldset#block-7-kind legend", exact_text: "Kind"
    assert_selector "#block-7-kind-errors", text: "is not included in the list"
  end

  test "a help line stands under the input and describes it" do
    field = Field.new(name: "title", type: :string, options: { help: "Empty: the kind's word." })
    render_inline Admin::Ui::FieldComponent.new(field:, form_name: "block[settings]", value: nil, locale: "en", id_prefix: "block-7")

    assert_selector "input#block-7-title[aria-describedby='block-7-title-help']"
    assert_selector "p#block-7-title-help.text-meta", exact_text: "Empty: the kind's word."
  end

  test "a placeholder handed to the field reaches its input" do
    field = Field.new(name: "title", type: :string, options: {})
    render_inline Admin::Ui::FieldComponent.new(field:, form_name: "block[settings]", value: nil, locale: "en", placeholder: { text: "Note" })

    assert_selector "input[placeholder='Note']"
  end

  # A drawing is written by the preview script only: on a translation tab it
  # has no original to read beside it, no label and no Translate button, and
  # keeps its error slot.
  test "a drawing on a translation tab is its hidden input and error slot, with no label and no reference card" do
    field = Field.new(name: "drawing", type: :diagram_drawing, options: { translated: true })
    original = { "svg" => "<svg/>", "from" => "a" * 64 }
    render_inline Admin::Ui::FieldComponent.new(field:, form_name: "block[settings]", value: nil, original: original, locale: "de",
      errors: [ "This drawing can't be shown on the site." ], id_prefix: "block-7")

    assert_selector "[data-field-name='drawing'] input[type=hidden]#block-7-drawing", visible: :all
    wrapper = page.find("[data-field-name='drawing']", visible: :all)
    assert_equal %w[admin-field admin-field--hidden], wrapper[:class].split, "no margin of its own"
    assert_equal %w[input div], wrapper.all(:xpath, "./*", visible: :all).map(&:tag_name), "the input and its error slot, nothing else"
    assert_no_selector "label, [data-original-for], [data-translate-slot] *", visible: :all
    assert_no_text "svg"
    assert_selector "#block-7-drawing-errors", text: "This drawing can't be shown on the site."
  end

  # The form is a column with a gap between its items: the drawing's wrapper
  # is no item until its error slot holds a message.
  test "a hidden field takes no room in the form: its wrapper is not drawn while its error slot is empty" do
    field = Field.new(name: "drawing", type: :diagram_drawing, options: { translated: true })
    render_inline Admin::Ui::FieldComponent.new(field:, form_name: "block[settings]", value: nil, locale: "en", id_prefix: "block-7")

    assert_selector ".admin-field--hidden #block-7-drawing-errors:not(:has(p))", visible: :all
    css = Rails.root.join("app/assets/tailwind/content-spiel.tailwind.css").read
    assert_match(/^\.admin-field--hidden:not\(:has\(p\)\) \{ display: none; \}$/, css)
    assert_includes Rails.root.join("app/views/admin/shared/_field_errors.html.erb").read, '<p class="flex gap-1.5">', "a message is a p, which the rule looks for"
  end
end
