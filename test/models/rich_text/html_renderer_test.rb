require "test_helper"

class RichText::HtmlRendererTest < ActiveSupport::TestCase
  def render(*content, preview: false)
    RichText::Document.new("type" => "doc", "content" => content).to_html(locale: "en", urls: PublicSite::Urls.new(preview: preview))
  end
  def text(value, *marks) = { "type" => "text", "text" => value, "marks" => marks }.compact

  test "standard nodes and marks" do
    html = render(
      { "type" => "heading", "attrs" => { "level" => 3 }, "content" => [ text("Title") ] },
      { "type" => "paragraph", "content" => [ text("a", { "type" => "bold" }), text("b", { "type" => "italic" }), { "type" => "hardBreak" }, text("c", { "type" => "code" }) ] },
      { "type" => "bulletList", "content" => [ { "type" => "listItem", "content" => [ { "type" => "paragraph", "content" => [ text("one") ] } ] } ] },
      { "type" => "blockquote", "content" => [ { "type" => "paragraph", "content" => [ text("q") ] } ] },
      { "type" => "codeBlock", "content" => [ text("x < y") ] },
      { "type" => "horizontalRule" })
    assert_includes html, "<h3>Title</h3>"
    assert_includes html, "<strong>a</strong><em>b</em><br><code>c</code>"
    assert_includes html, "<ul><li><p>one</p></li></ul>"
    assert_includes html, "<pre><code>x &lt; y</code></pre>"
    assert_includes html, "<hr>"
  end

  test "hostile documents render inert" do
    html = render(
      { "type" => "paragraph", "content" => [ text("<script>alert(1)</script>"),
        text("x", { "type" => "link", "attrs" => { "href" => "javascript:alert(1)" } }) ] },
      { "type" => "youtube", "attrs" => { "id" => "\"><iframe src=evil" } })
    assert_not_includes html, "<script>"
    assert_not_includes html, "javascript:"
    assert_not_includes html, "evil"
  end

  test "internal links resolve through public URLs, including preview" do
    page = create_page(title: "About")
    link = { "type" => "internalLink", "attrs" => { "type" => "page", "id" => page.id } }
    assert_includes render({ "type" => "paragraph", "content" => [ text("go", link) ] }), %(href="/about")
    assert_includes render({ "type" => "paragraph", "content" => [ text("go", link) ] }, preview: true), %(href="/preview/about")
  end

  test "missing asset and missing link target render gracefully" do
    link = { "type" => "internalLink", "attrs" => { "type" => "page", "id" => 0 } }
    html = render({ "type" => "paragraph", "content" => [ text("gone", link) ] }, { "type" => "image", "attrs" => { "asset_id" => 0 } })
    assert_includes html, "gone"
    assert_not_includes html, "<a"
    assert_not_includes html, "<img"
  end

  test "youtube renders the nocookie embed" do
    assert_includes render({ "type" => "youtube", "attrs" => { "id" => "dQw4w9WgXcQ" } }), "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"
  end

  test "unknown node types keep their text" do
    assert_includes render({ "type" => "marquee", "content" => [ text("kept") ] }), "kept"
  end
end
