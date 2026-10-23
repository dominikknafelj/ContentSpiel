require "test_helper"

class Admin::Fields::SelectFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "renders a select with options from a {value => label} hash" do
    field = Field.new(name: "role_type", type: :select, options: { options: { "ic" => "Individual contributor", "lead" => "Lead" } })
    render_inline Admin::Fields::SelectField.new(field:, form_name: "post[fields]", value: "ic", locale: "en")

    assert_selector "select[name='post[fields][role_type]']"
    assert_selector "option[value='ic'][selected]", text: "Individual contributor"
    assert_selector "option[value='lead']", text: "Lead"
  end

  test "renders options from a bare Array, valued and labelled the same" do
    field = Field.new(name: "size", type: :select, options: { options: %w[small medium large] })
    render_inline Admin::Fields::SelectField.new(field:, form_name: "post[fields]", value: "medium", locale: "en")

    assert_selector "option[value='medium'][selected]", text: "medium"
    assert_selector "option[value='small']", text: "small"
  end

  test "is the styled select" do
    field = Field.new(name: "size", type: :select, options: { options: %w[small medium] })
    render_inline Admin::Fields::SelectField.new(field:, form_name: "post[fields]", value: "small", locale: "en")

    assert_selector "select.cs-select[name='post[fields][size]']"
  end

  test "a select that is not required names its empty choice when the field says how, and leaves it unnamed otherwise" do
    named = Field.new(name: "language", type: :select, options: { options: { "ruby" => "Ruby" }, blank: "Plain text" })
    render_inline Admin::Fields::SelectField.new(field: named, form_name: "block[settings]", value: nil, locale: "en")
    assert_selector "option[value='']", text: "Plain text"

    unnamed = Field.new(name: "size", type: :select, options: { options: %w[small] })
    render_inline Admin::Fields::SelectField.new(field: unnamed, form_name: "block[settings]", value: nil, locale: "en")
    assert_equal "", page.find("option[value='']").text

    required = Field.new(name: "size", type: :select, options: { options: %w[small], required: true })
    render_inline Admin::Fields::SelectField.new(field: required, form_name: "block[settings]", value: "small", locale: "en")
    assert_no_selector "option[value='']"
  end

  # Note block spec, decision 7: a select may be drawn as a segmented control,
  # a group of radio buttons underneath, so it works from the keyboard and
  # without a script. The group is a fieldset named by its legend.
  test "a segmented select is a fieldset of radios named by its legend, the stored choice checked" do
    field = Field.new(name: "kind", type: :select, options: { options: { "note" => "Note", "tip" => "Tip" }, control: :segmented })
    render_inline Admin::Fields::SelectField.new(field:, form_name: "block[settings]", value: "tip", locale: "en", id_prefix: "block-7")

    assert_no_selector "select"
    assert_selector "fieldset#block-7-kind > legend", exact_text: "Kind"
    assert_selector "fieldset#block-7-kind input[type=radio]", count: 2
    assert_selector "fieldset#block-7-kind > div[class~='border-field-line']", count: 1
    assert_selector "label[for='block-7-kind-note'] input#block-7-kind-note[type=radio][name='block[settings][kind]'][value='note']:not([checked])"
    assert_selector "label[for='block-7-kind-tip'] input#block-7-kind-tip[type=radio][value='tip'][checked]"
    assert_selector "label[for='block-7-kind-tip']", text: "Tip"
  end

  test "a segmented select whose stored value is not on its list checks no button" do
    field = Field.new(name: "kind", type: :select, options: { options: { "note" => "Note" }, control: :segmented })
    render_inline Admin::Fields::SelectField.new(field:, form_name: "block[settings]", value: "gone", locale: "en")

    assert_no_selector "input[type=radio][checked]"
  end

  # A form someone else holds is rewritten by `HeldFields`: every radio is
  # disabled, and which one is checked stays.
  test "held by someone else, a segmented select keeps its checked button and disables every one" do
    field = Field.new(name: "kind", type: :select, options: { options: { "note" => "Note", "tip" => "Tip" }, control: :segmented })
    render_inline Admin::Fields::SelectField.new(field:, form_name: "block[settings]", value: "tip", locale: "en", id_prefix: "block-7")
    held = Nokogiri::HTML5.fragment(Admin::EditorScreen::HeldFields.call(rendered_content))

    assert_equal %w[disabled disabled], held.css("input[type=radio]").map { |radio| radio["disabled"] }
    assert_equal [ "tip" ], held.css("input[type=radio][checked]").map { |radio| radio["value"] }
  end
end
