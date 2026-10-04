require "test_helper"

# The rich-text column (tiptap spec §4.1): the `admin--rich-text` mount with
# its hidden JSON input (the editor's one contract with the server), the
# toolbar, the endpoint URLs and lookups the editor reads from `data-*`
# values, and -- in a translation -- the primary language's document
# rendered read-only. The editor itself is exercised in
# `test/system/admin/rich_text_test.rb`.
class Admin::Columns::RichTextColumnComponentTest < ViewComponent::TestCase
  def doc(markdown) = RichText::Document.from_markdown(markdown).first

  def controller_element = page.find("[data-controller='admin--rich-text']")

  test "renders the hidden JSON input inside the editor mount" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: doc("Hello **there**"))

    hidden = page.find("[data-controller='admin--rich-text'] input[type=hidden][name=body][data-admin--rich-text-target=input]", visible: false)
    assert_equal doc("Hello **there**").to_h, JSON.parse(hidden.value)
    assert_selector "[data-admin--rich-text-target=editor]"
  end

  test "no Markdown textarea any more" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: doc("Hi"))

    refute_selector "textarea"
    refute_includes rendered_content, "body_markdown"
  end

  test "accepts a raw document Hash or nil as the value" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: doc("Hi").to_h)
    assert_equal doc("Hi").to_h, JSON.parse(page.find("input[type=hidden][name=body]", visible: false).value)

    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil)
    hidden = page.find("input[type=hidden][name=body]", visible: false)
    assert_equal RichText::Document::EMPTY_HASH, JSON.parse(hidden.value)
  end

  test "renders spec §4.1's toolbar as plain buttons" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil)

    labels = page.all("[role=toolbar] button", visible: :all).map { |button| button["aria-label"] }
    assert_equal [ "Heading 2", "Heading 3", "Heading 4", "Bold", "Italic", "Strikethrough", "Inline code", "Bullet list",
      "Numbered list", "Quote", "Code block", "Link", nil, "Page link", "Image", "YouTube", "Divider" ], labels
    assert page.all("[role=toolbar] button", visible: :all).all? { |button| button["type"] == "button" }
  end

  test "the toolbar is a row of grouped tools with an Insert menu that wraps whole groups instead of spilling" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil)

    assert_selector "[role=toolbar].flex-wrap"
    assert_selector "[role=toolbar] [role=group].shrink-0", minimum: 3
    assert_selector "[role=toolbar] [role=separator]", minimum: 3
    assert_selector "[role=toolbar] [data-controller='admin--menu'] button[aria-haspopup=menu]", text: "Insert"
    %w[Image YouTube].each do |label|
      assert_selector "[role=toolbar] [role=menu] button", text: label, visible: :all
    end
    assert_no_selector "[role=toolbar] > button", text: "Image"
    # Every menu item closes the menu before its command runs.
    assert page.all("[role=menu] button", visible: :all).all? { |button| button["data-action"].include?("click->admin--menu#close") }
  end

  # Only toggle buttons announce a pressed state; the ones that open a
  # popover or insert something aren't toggles.
  test "aria-pressed only on the toggle buttons" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil)

    pressed = page.all("[role=toolbar] button[aria-pressed]", visible: :all).map { |button| button["aria-label"] }
    assert_equal [ "Heading 2", "Heading 3", "Heading 4", "Bold", "Italic", "Strikethrough", "Inline code", "Bullet list",
      "Numbered list", "Quote", "Code block" ], pressed
    assert_selector "[role=toolbar] button[aria-label='Link'][aria-haspopup=dialog]"
  end

  # Media library Task 8: the Image button opens the media picker (a
  # dialog) and the picked asset arrives as `media-picker:picked` -- the
  # editor has no file input or upload endpoint of its own any more.
  test "the Image button opens the media picker instead of a file input" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil)

    assert_selector "[role=toolbar] button[aria-label='Image'][aria-haspopup=dialog]", visible: :all
    assert_no_selector "input[type=file]", visible: :all
    assert_includes controller_element["data-action"], "media-picker:picked->admin--rich-text#picked"
    assert_nil controller_element["data-admin--rich-text-upload-url-value"]
  end

  test "endpoint URLs come from the route helpers, and the editing locale is passed along" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil, locale: "de")

    assert_equal "/#{ContentSpiel::ADMIN_PATH}/link_targets", controller_element["data-admin--rich-text-link-targets-url-value"]
    assert_equal "de", controller_element["data-admin--rich-text-locale-value"]
  end

  test "without a locale the editor edits the primary language" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil)

    assert_equal Locales.default.to_s, controller_element["data-admin--rich-text-locale-value"]
  end

  # Only what still exists is listed -- a deleted asset or link target is
  # absent, which the editor shows as "missing" (spec §7).
  test "passes URLs and default alt/caption for the document's images and titles for its internal links" do
    asset = create_media_asset
    asset.update!(alt: "A dog", caption: "Our dog")
    target = create_page(title: "Contact")
    document = { "type" => "doc", "content" => [
      { "type" => "image", "attrs" => { "asset_id" => asset.id, "alt" => "", "caption" => "" } },
      { "type" => "image", "attrs" => { "asset_id" => asset.id + 1000, "alt" => "", "caption" => "" } },
      { "type" => "paragraph", "content" => [
        { "type" => "text", "text" => "here", "marks" => [ { "type" => "internalLink", "attrs" => { "type" => "page", "id" => target.id } } ] },
        { "type" => "text", "text" => "gone", "marks" => [ { "type" => "internalLink", "attrs" => { "type" => "post", "id" => 999_999 } } ] }
      ] }
    ] }

    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: document)

    assert_equal({ asset.id.to_s => { "url" => asset.url, "alt" => "A dog", "caption" => "Our dog" } },
      JSON.parse(controller_element["data-admin--rich-text-assets-value"]))
    assert_equal({ "page:#{target.id}" => "Contact" }, JSON.parse(controller_element["data-admin--rich-text-link-titles-value"]))
  end

  # The image defaults are read in the column's editing locale, falling
  # back the way the public page does (no German caption: the English one).
  test "image defaults are resolved in the editing locale" do
    asset = create_media_asset
    asset.update!(alt: "A dog", caption: "Our dog")
    Mobility.with_locale(:de) { asset.update!(alt: "Ein Hund") }
    document = { "type" => "doc", "content" => [ { "type" => "image", "attrs" => { "asset_id" => asset.id, "alt" => "", "caption" => "" } } ] }

    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: document, locale: "de")

    assert_equal({ "url" => asset.url, "alt" => "Ein Hund", "caption" => "Our dog" },
      JSON.parse(controller_element["data-admin--rich-text-assets-value"])[asset.id.to_s])
  end

  test "renders the default-locale original as html, labelled, with the translate slot" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: nil, original: doc("Hallo **Welt**"))

    assert_selector "[data-original-for=body] strong", text: "Welt"
    assert_selector "[data-translate-slot=body]", visible: :all
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

  # A caller nesting this under a form object (`Admin::BlockCardComponent`,
  # `Admin::PostFormComponent`) needs the input's own `name=` to carry that
  # nesting (`post[body]`), not the bare column name `name:` only drives the
  # label/`data-field-name` for.
  test "an explicit html_name, not the bare name, drives the input's own name" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", html_name: "post[body]", value: doc("Hello"))

    assert_selector "input[type=hidden][name='post[body]']", visible: false
    refute_selector "input[type=hidden][name=body]", visible: false
  end

  test "renders the error slot keyed off the id" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", id: "post-body", value: nil, errors: [ "Body is invalid" ])

    assert_selector "#post-body-errors", text: "Body is invalid"
    assert_selector "#post-body-editor[data-admin--rich-text-target=editor][data-labelledby=post-body-label]"
  end
end

class Admin::Columns::RichTextColumnComponentTranslationTest < ViewComponent::TestCase
  def doc(markdown) = RichText::Document.from_markdown(markdown).first

  test "an outdated translation shows the note beside the rendered original" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: doc("Hallo"), original: doc("Hello again"), locale: "de",
      translation_state: :outdated, translation_confirm: { record_type: "Post", record_id: 2, field: "body", locale: "de" })

    assert_selector "[data-original-for='body'] #translation-note-post-2-body button", text: "Mark as up to date"
  end

  test "a current translation shows no note" do
    render_inline Admin::Columns::RichTextColumnComponent.new(name: "body", value: doc("Hallo"), original: doc("Hello"), locale: "de",
      translation_state: :current, translation_confirm: { record_type: "Post", record_id: 2, field: "body", locale: "de" })

    refute_text "Original changed since this was translated"
  end
end
