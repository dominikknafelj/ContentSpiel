require "test_helper"

class Admin::Fields::CodeFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  def render_field(value, **options)
    field = Field.new(name: "code", type: :code, options: options)
    render_inline Admin::Fields::CodeField.new(field:, form_name: "block[settings]", value: value, locale: "en", id_prefix: "block-7")
  end

  def counter = "p#block-7-code-count"

  test "a monospace textarea of twelve rows that neither wraps nor corrects, with the code as typed and no maxlength" do
    render_field("  def a\n\tb", max: 20_000)

    assert_selector "textarea#block-7-code[name='block[settings][code]'][rows='12'][wrap='off'][spellcheck='false'][autocapitalize='off'][autocomplete='off']"
    assert_selector "textarea.font-cs-mono.whitespace-pre.overflow-auto"
    assert_includes page.find("textarea")[:class], "[tab-size:2]"
    assert_equal "  def a\n\tb", Nokogiri::HTML5.fragment(rendered_content).at_css("textarea").text
    assert_no_selector "textarea[maxlength]"
  end

  test "the counter is in the page and hidden below nine tenths of the limit, reads the count from there, and warns over the limit" do
    render_field("x" * 17_999, max: 20_000)
    assert_selector "#{counter}[hidden]", visible: :all

    render_field("x" * 18_000, max: 20_000)
    assert_selector "#{counter}:not([hidden])", text: "18,000 of 20,000"

    render_field("x" * 18_412, max: 20_000)
    assert_selector "#{counter}.text-meta:not([hidden])", text: "18,412 of 20,000"

    render_field("x" * 20_001, max: 20_000)
    assert_selector "#{counter}.text-warn-ink:not([hidden])", text: "20,001 of 20,000"
  end

  test "the counter's script has the limit, where it starts, its one message, and reads the field" do
    render_field("x", max: 20_000)

    wrapper = page.find("[data-controller='admin--editor--code-limit']")
    assert_equal "20000", wrapper["data-admin--editor--code-limit-limit-value"]
    assert_equal "18000", wrapper["data-admin--editor--code-limit-from-value"]
    assert_equal "%{used} of %{limit}", JSON.parse(wrapper["data-messages"]).fetch("components.fields.code_field.count")
    assert_selector "textarea[data-admin--editor--code-limit-target='input'][data-action='input->admin--editor--code-limit#update'][aria-describedby='block-7-code-count']"
    assert_selector "#{counter}[data-admin--editor--code-limit-target='output']", visible: :all
  end

  test "without a limit there is no counter and no script" do
    render_field("x")

    assert_selector "textarea#block-7-code"
    assert_no_selector "[data-controller], [data-action], p", visible: :all
  end
end
