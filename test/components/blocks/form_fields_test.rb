require "test_helper"

# The five public inputs (forms plan, Task 1). Placeholder look: the default
# theme's field styles; what is held here is the markup's accessibility.
class Blocks::FormFieldsTest < ViewComponent::TestCase
  def field_of(type, label: "Your name", required: false, help: nil, **settings)
    Forms::Field.from_h("key" => "f_abcd1234", "type" => type, "required" => required,
      "label" => { "en" => label }, "help" => (help ? { "en" => help } : {}), "settings" => settings)
  end

  def draw(field, value: nil, error: nil, locale: "en", place: 11)
    public_field = Forms::PublicField.new(field: field, locale: locale, form_id: 3, place: place)
    render_inline public_field.input.new(field: public_field, value: value, error: error)
  end

  test "each input has a real label that says required in words when required" do
    %w[short_text long_text email].each do |type|
      draw(field_of(type, required: true))
      assert_selector "label[for='form-11-f_abcd1234']", text: "Your name"
      assert_selector "label[for='form-11-f_abcd1234']", text: "required"
      assert_selector "[name='answers[f_abcd1234]'][id='form-11-f_abcd1234'][required]"
    end

    draw(field_of("short_text"))
    assert_no_selector "label", text: "required"
    assert_no_selector "[required]"

    draw(field_of("checkbox", required: true, label: "I agree"))
    assert_selector "label[for='form-11-f_abcd1234']", text: "I agree"
    assert_selector "label", text: "required"
  end

  test "an error links the control to its message with aria-describedby and aria-invalid" do
    draw(field_of("short_text", help: "As on your passport"), value: "x", error: :blank)

    assert_selector "input[aria-invalid='true'][aria-describedby='form-11-f_abcd1234-help form-11-f_abcd1234-error']"
    assert_selector "#form-11-f_abcd1234-error", text: "Please fill in this field."
    assert_selector "#form-11-f_abcd1234-help", text: "As on your passport"
    assert_selector "input[value='x']"

    draw(field_of("short_text"))
    assert_no_selector "[aria-invalid]"
    assert_no_selector "[aria-describedby]"
    assert_no_selector "#form-11-f_abcd1234-error"

    { blank: "Please fill in this field.", invalid: "Please check this entry.", inclusion: "Please choose one of the options.", too_long: "This is too long." }.each do |error, words|
      draw(field_of("short_text"), error: error)
      assert_selector "#form-11-f_abcd1234-error", text: words
    end
  end

  test "a label that looks like markup is text" do
    draw(field_of("short_text", label: "<script>alert(1)</script><b>x</b>", help: "<img src=x onerror=alert(1)>"))

    assert_no_selector "script"
    assert_no_selector "img"
    assert_no_selector "label b"
    assert_selector "label", text: "<script>alert(1)</script><b>x</b>"
  end

  test "a choice drawn as radios is a fieldset with a legend" do
    choices = [ { "key" => "c_aaaaaaaa", "label" => { "en" => "Press" } }, { "key" => "c_bbbbbbbb", "label" => { "en" => "Other" } } ]
    draw(field_of("choice", label: "Topic", required: true, display: "radios", choices: choices), value: "c_bbbbbbbb", error: :blank)

    assert_selector "fieldset[aria-describedby='form-11-f_abcd1234-error'] legend", text: "Topic"
    assert_selector "legend", text: "required"
    assert_no_selector "fieldset[aria-invalid]"
    assert_selector "input[type=radio][aria-invalid='true']", count: 2
    assert_selector "input[type=radio][name='answers[f_abcd1234]']", count: 2
    assert_selector "input[type=radio][value='c_bbbbbbbb'][checked]"
    assert_selector "input[type=radio][value='c_aaaaaaaa']:not([checked])"
    assert_selector "label", text: "Press"
    assert_selector "#form-11-f_abcd1234-error"
    assert_no_selector "select"
  end

  test "a choice drawn as a dropdown is a select with the choose word first and its label" do
    choices = [ { "key" => "c_aaaaaaaa", "label" => { "en" => "Press", "de" => "Presse" } } ]
    draw(field_of("choice", label: "Topic", display: "dropdown", choices: choices), value: "c_aaaaaaaa")

    assert_selector "label[for='form-11-f_abcd1234']", text: "Topic"
    assert_selector "select#form-11-f_abcd1234[name='answers[f_abcd1234]'] option:first-child", text: "Choose"
    assert_selector "option[value='c_aaaaaaaa'][selected]", text: "Press"

    draw(field_of("choice", label: "Thema", display: "dropdown", choices: choices), locale: "de")
    assert_selector "option[value='c_aaaaaaaa']", text: "Presse"
  end

  test "a checkbox has its label after the box and sends nothing when unticked" do
    draw(field_of("checkbox", label: "I agree"), value: true)

    assert_selector "input[type=checkbox][name='answers[f_abcd1234]'][value='1'][checked]"
    html = rendered_content
    assert_operator html.index("<input"), :<, html.index("I agree"), "the label follows the box"
  end

  test "maxlength is the type's limit on text inputs and absent on a choice" do
    draw(field_of("short_text"))
    assert_selector "input[maxlength='500']"
    draw(field_of("long_text"))
    assert_selector "textarea[maxlength='5000']"
    draw(field_of("email"))
    assert_selector "input[type=email]"
    assert_no_selector "[maxlength]"
    draw(field_of("choice", display: "dropdown", choices: []))
    assert_no_selector "[maxlength]"
    draw(field_of("checkbox"))
    assert_no_selector "[maxlength]"
  end

  test "two placements of one form have distinct ids" do
    ids = [ 11, 12 ].map { |place| draw(field_of("short_text"), place: place); page.find("input")[:id] }
    assert_equal 2, ids.uniq.size
  end

  test "a choice label and a typed value that look like markup are escaped, and a choice with no label is left out" do
    choices = [ { "key" => "c_aaaaaaaa", "label" => { "en" => "<img src=x onerror=alert(1)>" } }, { "key" => "c_bbbbbbbb", "label" => {} } ]
    [ "radios", "dropdown" ].each do |display|
      draw(field_of("choice", display: display, choices: choices))
      assert_no_selector "img"
      assert_text "<img src=x onerror=alert(1)>"
      assert_no_selector "[value='c_bbbbbbbb']"
      assert_no_text "c_bbbbbbbb"
    end

    draw(field_of("short_text"), value: %("><script>alert(1)</script>))
    assert_no_selector "script"
    assert_equal %("><script>alert(1)</script>), page.find("input").value
    draw(field_of("long_text"), value: "</textarea><script>alert(1)</script>")
    assert_no_selector "script"
  end

  test "only the email input asks for autocomplete email" do
    draw(field_of("email"))
    assert_selector "input[autocomplete='email']"
    draw(field_of("short_text"))
    assert_no_selector "[autocomplete]"
  end
end
