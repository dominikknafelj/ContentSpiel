require "test_helper"

# The interim rich-text column (Task 5 until Task 7 swaps in Tiptap): a
# hidden input carrying the document JSON (the contract Tiptap will write
# to), a Markdown `<textarea>` editors actually type into, and -- in a
# translation -- the primary language's document rendered read-only.
class Admin::Columns::RichTextColumnComponentTest < ViewComponent::TestCase
  def doc(markdown) = RichText::Document.from_markdown(markdown).first

  test "renders the hidden JSON input and a Markdown textarea named after the column" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: doc("Hello **there**"))

    hidden = page.find("input[type=hidden][name=body]", visible: false)
    assert_equal doc("Hello **there**").to_h, JSON.parse(hidden.value)
    assert_selector "textarea[name=body_markdown]", text: "Hello **there**"
  end

  test "accepts a raw document Hash or nil as the value" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: doc("Hi").to_h)
    assert_selector "textarea[name=body_markdown]", text: "Hi"

    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil)
    hidden = page.find("input[type=hidden][name=body]", visible: false)
    assert_equal RichText::Document::EMPTY_HASH, JSON.parse(hidden.value)
  end

  test "renders the default-locale original as html, labelled" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil, original: doc("Hallo **Welt**"))

    assert_selector "[data-original-for=body] strong", text: "Welt"
    assert_text Locales.name(Locales.default, native: true)
  end

  # Fix round 1 (m2): the read-only original is rendered HTML, so markup
  # typed as *text* in the primary language must come out escaped, never
  # live.
  test "the original escapes script tags and event handlers typed as text" do
    original = { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [
      { "type" => "text", "text" => %(<script>alert(1)</script><b onclick="x()">bold</b>) } ] } ] }

    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil, original: original)

    refute_selector "[data-original-for=body] script", visible: :all
    refute_selector "[data-original-for=body] b"
    refute_selector "[onclick]"
    assert_includes rendered_content, "&lt;script&gt;"
    assert_selector "[data-original-for=body]", text: %(<script>alert(1)</script><b onclick="x()">bold</b>)
  end

  test "no original column when none is given, or when the original is blank" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: doc("Hello"))
    refute_selector "[data-original-for]"

    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: doc("Hello"), original: RichText::Document.empty)
    refute_selector "[data-original-for]"
  end

  # Fix round 1 (Task 7 review): a caller nesting this under a form object
  # (`Admin::BlockCardComponent`, `Admin::PostFormComponent`) needs the
  # inputs' own `name=` to carry that nesting (`block[body]`/`post[body]`),
  # not the bare column name `name:` only drives the label/`data-field-name`
  # for -- the Markdown textarea nests the same way (`post[body_markdown]`).
  test "an explicit html_name, not the bare name, drives the inputs' own names" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", html_name: "post[body]", value: doc("Hello"))

    assert_selector "input[type=hidden][name='post[body]']", visible: false
    assert_selector "textarea[name='post[body_markdown]']"
    refute_selector "input[type=hidden][name=body]", visible: false
  end

  test "renders error and warning slots keyed off the id" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", id: "post-body", value: nil, errors: [ "Body is invalid" ])

    assert_selector "#post-body-errors", text: "Body is invalid"
    assert_selector "#post-body-warnings"
  end
end
