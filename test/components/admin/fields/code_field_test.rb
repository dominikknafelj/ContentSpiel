require "test_helper"

class Admin::Fields::CodeFieldTest < ViewComponent::TestCase
  Field = ContentModel::Definition::Field

  def render_field(value, **options)
    field = Field.new(name: "code", type: :code, options: options)
    render_inline Admin::Fields::CodeField.new(field:, form_name: "block[settings]", value: value, locale: "en", id_prefix: "block-7")
  end

  def counter = "p#block-7-code-count"

  test "a monospace textarea that neither wraps nor corrects, with the code as typed and no maxlength" do
    render_field("  def a\n\tb", max: 20_000)

    assert_selector "textarea#block-7-code[name='block[settings][code]'][wrap='off'][spellcheck='false'][autocapitalize='off'][autocomplete='off']"
    assert_selector "textarea.font-cs-mono.text-sm.whitespace-pre.overflow-auto"
    assert_includes page.find("textarea")[:class], "[tab-size:2]"
    assert_equal "  def a\n\tb", Nokogiri::HTML5.fragment(rendered_content).at_css("textarea").text
    assert_no_selector "textarea[maxlength]"
  end

  # Design answer C3. The browser test holds the heights; this holds that
  # they are the stylesheet's (nothing measures the field) and what a
  # browser without `field-sizing` falls back to.
  test "the field's height is the code's, between six and twenty-four lines, by classes alone, with twelve rows as the fallback" do
    render_field("a", max: 20_000)

    classes = page.find("textarea")[:class].split
    assert_includes classes, "[field-sizing:content]"
    assert_includes classes, "min-h-[calc(6lh+1rem+2px)]"
    assert_includes classes, "max-h-[calc(24lh+1rem+2px)]"
    assert_includes classes, "w-full", "the width stays the form's: field-sizing would otherwise follow the longest line"
    assert_includes classes, "py-2", "the 1rem in the two heights is this padding"
    assert_selector "textarea[rows='12']"
    assert_no_selector "[data-controller*='grow'], textarea[style]"
  end

  # Task 2's review, Minor 6: a browser drops one line break directly after
  # `<textarea>`. Rails writes one of its own there, so the value's stays;
  # a hand-written tag would lose a line of the code without a word.
  test "a value that begins with a line break keeps it in the field's markup" do
    render_field("\n  a\n", max: 20_000)

    assert_equal "\n  a\n", Nokogiri::HTML5.fragment(rendered_content).at_css("textarea").text
  end

  # Design answer C4.
  test "the counter is in the page and hidden below nine tenths of the limit, reads the count with its unit from there, and over the limit says by how much in the danger ink" do
    render_field("x" * 17_999, max: 20_000)
    assert_selector "#{counter}[hidden]", visible: :all

    render_field("x" * 18_000, max: 20_000)
    assert_selector "#{counter}:not([hidden])", exact_text: "18,000 of 20,000 characters"

    render_field("x" * 18_412, max: 20_000)
    assert_selector "#{counter}.text-meta:not([hidden])", exact_text: "18,412 of 20,000 characters"

    render_field("x" * 20_000, max: 20_000)
    assert_selector "#{counter}.text-meta:not([hidden])", exact_text: "20,000 of 20,000 characters"

    render_field("x" * 20_412, max: 20_000)
    assert_selector "#{counter}.text-danger-ink:not([hidden])", exact_text: "20,412 of 20,000 characters · 412 over"
    assert_no_selector "#{counter}.text-meta, #{counter}.text-warn-ink"

    render_field("x" * 21_500, max: 20_000)
    assert_selector counter, exact_text: "21,500 of 20,000 characters · 1,500 over"
  end

  # Task 2's review, Minor 5: nine tenths in whole numbers. As a float,
  # `70 * 0.9` is 62.99… and the counter would show one character early.
  test "the counter starts at nine tenths of the limit, counted in whole numbers" do
    render_field("x" * 62, max: 70)
    assert_selector "#{counter}[hidden]", visible: :all
    assert_equal "63", page.find("[data-controller='admin--editor--code-limit']")["data-admin--editor--code-limit-from-value"]

    render_field("x" * 63, max: 70)
    assert_selector "#{counter}:not([hidden])", exact_text: "63 of 70 characters"
  end

  test "the counter is the field's description only while it shows, and the line that announces it is a polite region the server leaves empty" do
    render_field("x" * 17_999, max: 20_000)
    assert_no_selector "textarea[aria-describedby]"
    assert_selector "p.sr-only[aria-live='polite'][data-admin--editor--code-limit-target='announcer']", exact_text: "", visible: :all

    render_field("x" * 18_000, max: 20_000)
    assert_selector "textarea[aria-describedby='block-7-code-count']"
    assert_selector "p.sr-only[aria-live='polite'][data-admin--editor--code-limit-target='announcer']", exact_text: "", visible: :all
    assert_no_selector "#{counter}[aria-live], #{counter}[role]", visible: :all
  end

  test "the counter's script has the limit, where it starts, its two messages, and reads the field" do
    render_field("x", max: 20_000)

    wrapper = page.find("[data-controller='admin--editor--code-limit']")
    assert_equal "20000", wrapper["data-admin--editor--code-limit-limit-value"]
    assert_equal "18000", wrapper["data-admin--editor--code-limit-from-value"]
    served = JSON.parse(wrapper["data-messages"])
    assert_equal "%{used} of %{limit} characters", served.fetch("components.fields.code_field.count")
    assert_equal "%{used} of %{limit} characters · %{over} over", served.fetch("components.fields.code_field.over")
    assert_selector "textarea[data-admin--editor--code-limit-target='input'][data-action='input->admin--editor--code-limit#update']"
    assert_selector "#{counter}[data-admin--editor--code-limit-target='output']", visible: :all
  end

  test "without a limit there is no counter and no script" do
    render_field("x")

    assert_selector "textarea#block-7-code"
    assert_no_selector "[data-controller], [data-action], p", visible: :all
  end
end
