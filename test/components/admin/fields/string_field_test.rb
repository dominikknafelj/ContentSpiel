require "test_helper"

class Admin::Fields::StringFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  test "renders a text input named and valued" do
    field = Field.new(name: "title", type: :string, options: {})
    render_inline Admin::Fields::StringField.new(field:, form_name: "post[fields]", value: "Hello", locale: "en")

    assert_selector "input[type=text][name='post[fields][title]'][value='Hello']"
  end

  test "a required field renders the required attribute" do
    field = Field.new(name: "title", type: :string, options: { required: true })
    render_inline Admin::Fields::StringField.new(field:, form_name: "post[fields]", value: nil, locale: "en")

    assert_selector "input[required]"
  end

  test "a placeholder handed over is the input's, and one that follows a choice wires the script with the choice's name and labels" do
    field = Field.new(name: "title", type: :string, options: { placeholder_from: :kind })
    render_inline Admin::Fields::StringField.new(field:, form_name: "block[settings]", value: nil, locale: "en", id_prefix: "block-7",
      placeholder: { text: "Tip", source: "block[settings][kind]", labels: { "note" => "Note", "tip" => "Tip" } })

    input = page.find("input#block-7-title")
    assert_equal "Tip", input[:placeholder]
    assert_equal "admin--ui--placeholder-from", input["data-controller"]
    assert_equal "block[settings][kind]", input["data-admin--ui--placeholder-from-source-value"]
    assert_equal({ "note" => "Note", "tip" => "Tip" }, JSON.parse(input["data-admin--ui--placeholder-from-labels-value"]))
  end

  test "without a placeholder or a help line the input has neither, and no script" do
    field = Field.new(name: "title", type: :string, options: {})
    render_inline Admin::Fields::StringField.new(field:, form_name: "post[fields]", value: nil, locale: "en")

    assert_no_selector "input[placeholder], input[aria-describedby], input[data-controller]"
  end
end
