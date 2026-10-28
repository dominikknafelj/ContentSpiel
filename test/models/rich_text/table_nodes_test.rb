require "test_helper"

# The four table nodes (table block spec, decision 2): rows of cells, a cell
# one paragraph of inline content. Where a table may be is the body rule's
# (`test/models/content_block_table_body_test.rb`).
class RichText::TableNodesTest < ActiveSupport::TestCase
  def text(value, *marks) = { "type" => "text", "text" => value, "marks" => marks }.compact
  def paragraph(*inline) = { "type" => "paragraph", "content" => inline }
  def cell(*inline, type: "tableCell", align: nil) = { "type" => type, "attrs" => ({ "align" => align } if align), "content" => [ paragraph(*inline) ] }.compact
  def table(*rows) = { "type" => "table", "content" => rows.map { |cells| { "type" => "tableRow", "content" => cells } } }
  def document(*nodes) = RichText::Document.new("type" => "doc", "content" => nodes)

  test "a table of header and plain cells with inline marks validates" do
    link = { "type" => "link", "attrs" => { "href" => "https://example.com" } }
    doc = document(table(
      [ cell(text("Name", { "type" => "bold" }), type: "tableHeader"), cell(text("Link"), type: "tableHeader", align: "right") ],
      [ cell(text("a")), cell(text("b", link), align: "center") ]
    ))
    assert_equal [], doc.validate
  end

  test "a cell holding a list, an image or two paragraphs is refused" do
    list = { "type" => "bulletList", "content" => [ { "type" => "listItem", "content" => [ paragraph(text("x")) ] } ] }
    image = { "type" => "image", "attrs" => { "asset_id" => 1 } }
    {
      "list" => [ list ],
      "image" => [ image ],
      "two paragraphs" => [ paragraph(text("a")), paragraph(text("b")) ]
    }.each do |name, content|
      bad = { "type" => "tableCell", "content" => content }
      errors = document(table([ bad ])).validate
      assert errors.any? { |error| error.include?("tableCell") }, "#{name}: #{errors.inspect}"
    end
  end

  test "an unknown align is refused" do
    errors = document(table([ cell(text("a"), align: "justify") ])).validate
    assert_includes errors, "tableCell.align must be one of left, center, right"
  end

  test "the renderer draws th scope=col for a header row, td otherwise, and the alignment as a class" do
    html = document(table(
      [ cell(text("H"), type: "tableHeader", align: "left") ],
      [ cell(text("v"), align: "right") ],
      [ cell(text("w")) ]
    )).to_html(locale: "en")
    assert_includes html, %(<th scope="col" class="align-left">H</th>)
    assert_includes html, %(<td class="align-right">v</td>)
    assert_includes html, "<td>w</td>"
    assert_includes html, "<table><tbody><tr>"
    assert_not_includes html, "<p>"
  end

  test "a class that is not a cell's alignment does not survive the scrubber" do
    html = RichTextScrubber.new.then { |scrubber| Rails::HTML5::SafeListSanitizer.new.sanitize(%(<p class="align-left">a</p><table><tbody><tr><td class="evil">b</td><td class="align-center">c</td></tr></tbody></table>), scrubber: scrubber) }
    assert_not_includes html, "evil"
    assert_not_includes html, %(<p class)
    assert_includes html, %(<td class="align-center">)
  end

  test "render_fragment draws a cell's inline content with its marks and no paragraph" do
    document = self.document(paragraph)
    nodes = [ text("a ", { "type" => "bold" }), text("<b>b</b>") ]
    html = RichText::HtmlRenderer.new(RichText::RenderContext.new(locale: "en", urls: PublicSite::Urls.new, document: document)).render_fragment(nodes)
    assert_includes html, "<strong>a </strong>"
    assert_includes html, "&lt;b&gt;b&lt;/b&gt;"
    assert_not_includes html, "<p>"
    assert_predicate html, :html_safe?
  end

  # `render_fragments` is `render_fragment` for many lists at once, from one
  # parse: every answer is the one the cell would get alone, whatever is in
  # it (marks, a link, a line break, text that looks like markup, a stray
  # cell node of a hand-made body, nothing at all), and the wrappers it draws
  # them in never reach a cell.
  test "render_fragments answers what render_fragment answers for each list, from one sanitizer pass" do
    link = { "type" => "link", "attrs" => { "href" => "https://example.com" } }
    lists = [
      [ text("a ", { "type" => "bold" }), text("<b>b</b>") ],
      [ text("go", link), { "type" => "hardBreak" }, text("on", { "type" => "italic" }) ],
      [],
      "not a list",
      [ { "type" => "tableCell", "content" => [ paragraph(text("stray")) ] }, text("</div><div>x") ],
      [ text("<script>alert(1)</script>") ]
    ]
    renderer = RichText::HtmlRenderer.new(RichText::RenderContext.new(locale: "en", urls: PublicSite::Urls.new, document: document(paragraph)))
    alone = lists.map { |nodes| renderer.render_fragment(nodes) }

    together, parses = SanitizerParses.during { renderer.render_fragments(lists) }
    assert_equal 1, parses, "one parse and one scrubber pass for every list"
    assert_equal alone, together
    assert together.all?(&:html_safe?)
    assert together.none? { |html| html.include?("<div") }
    assert_equal [], renderer.render_fragments([])
  end
end
