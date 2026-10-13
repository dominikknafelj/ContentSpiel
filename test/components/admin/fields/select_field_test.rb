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
end
