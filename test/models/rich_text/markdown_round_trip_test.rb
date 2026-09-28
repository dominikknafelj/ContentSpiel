require "test_helper"

# Final fix wave (B): editor-shaped documents -- what Tiptap actually
# produces, not just one node of each type -- round-trip through Markdown
# unchanged. The comparison is over `RichText::Document#normalized` (the
# form `assign_body` stores): marks in schema order, and whitespace at the
# edges of a bold/italic/strike run moved outside the mark, since Markdown
# can't delimit emphasis there (`**bold **` isn't bold).
#
# Every fixture must also be valid (the editor's content model), so a
# fixture can't quietly test a shape the editor could never produce.
class RichText::MarkdownRoundTripTest < ActiveSupport::TestCase
  def text(value, *marks) = { "type" => "text", "text" => value }.merge(marks.empty? ? {} : { "marks" => marks.map { |mark| mark.is_a?(Hash) ? mark : { "type" => mark } } })
  def paragraph(*content) = { "type" => "paragraph", "content" => content }
  def item(*content) = { "type" => "listItem", "content" => content }
  def bullets(*items) = { "type" => "bulletList", "content" => items }
  def hard_break = { "type" => "hardBreak" }
  def youtube = { "type" => "youtube", "attrs" => { "id" => "dQw4w9WgXcQ" } }
  def link(href) = { "type" => "link", "attrs" => { "href" => href } }

  def assert_round_trips(*content)
    document = RichText::Document.new("type" => "doc", "content" => content).normalized
    assert_empty document.validate, "fixture isn't a valid document: #{document.to_h.inspect}"

    markdown = document.to_markdown
    reloaded, warnings = RichText::Document.from_markdown(markdown)
    assert_equal document.to_h, reloaded.normalized.to_h, "round trip changed the document; markdown was:\n#{markdown}"
    assert_empty warnings, "markdown was:\n#{markdown}"
    markdown
  end

  test "embeds inside list items and blockquotes" do
    asset = create_media_asset
    image = { "type" => "image", "attrs" => { "asset_id" => asset.id, "alt" => "A", "caption" => "C" } }

    assert_round_trips(bullets(item(paragraph(text("watch")), youtube, image)))
    assert_round_trips(bullets(item({ "type" => "paragraph", "content" => [] }, youtube)))
    assert_round_trips({ "type" => "blockquote", "content" => [ youtube ] })
    assert_round_trips({ "type" => "blockquote", "content" => [ paragraph(text("quote")), image ] })
  end

  test "bold, italic and strike with leading or trailing spaces" do
    markdown = assert_round_trips(paragraph(text("a"), text(" bold ", "bold"), text("b")))
    assert_includes markdown, "a **bold** b"
    assert_round_trips(paragraph(text("x"), text(" it", "italic"), text(" and "), text("gone ", "strike"), text("y")))
    assert_round_trips(paragraph(text(" lead", "bold", "italic")))
  end

  test "a whitespace-only emphasis run loses the mark instead of becoming literal asterisks" do
    document = RichText::Document.new("type" => "doc", "content" => [ paragraph(text("a"), text(" ", "bold"), text("b")) ])
    assert_equal [ text("a b") ], document.normalized.to_h.dig("content", 0, "content")
  end

  test "a hard break followed by text that looks like a block marker" do
    [ "- flour", "# x", "> y", "---", "===", "1. step", "+ more", "| a |", "    indented", "\ttabbed" ].each do |line|
      assert_round_trips(paragraph(text("Ingredients:"), hard_break, text(line)))
    end
  end

  test "leading and trailing whitespace in a paragraph" do
    assert_round_trips(paragraph(text("    four spaces")))
    assert_round_trips(paragraph(text("  two"), hard_break, text("  after")))
    assert_round_trips(paragraph(text("trailing  ")))
    assert_round_trips({ "type" => "heading", "attrs" => { "level" => 2 }, "content" => [ text(" spaced heading ") ] })
    assert_round_trips({ "type" => "heading", "attrs" => { "level" => 3 }, "content" => [ text("ends with #") ] })
  end

  test "a code block containing a fence" do
    markdown = assert_round_trips({ "type" => "codeBlock", "attrs" => { "language" => "md" }, "content" => [ text("```ruby\nputs 1\n```") ] })
    assert markdown.start_with?("````md\n"), markdown
    assert_round_trips({ "type" => "codeBlock", "content" => [ text("````\n``") ] })
    assert_round_trips({ "type" => "codeBlock" })
  end

  test "nested lists with marks" do
    inner = bullets(item(paragraph(text("deep", "italic", link("https://example.com/a b")), text(" and "), text("code", "code"))))
    assert_round_trips(bullets(
      item(paragraph(text("one", "bold"), text(" plain")), inner),
      item(paragraph(text("two"))),
    ))
    assert_round_trips({ "type" => "orderedList", "attrs" => { "start" => 3 }, "content" => [
      item(paragraph(text("three", "strike")), { "type" => "orderedList", "attrs" => { "start" => 1 }, "content" => [ item(paragraph(text("a", "bold", "italic"))) ] })
    ] })
  end

  test "a code span with spaces at both ends" do
    assert_round_trips(paragraph(text("x "), text(" y ", "code"), text(" z")))
  end

  # Accepted lossiness, not corruption: an ATX heading is one line, so a
  # hardBreak inside one becomes a space, and a hardBreak ending a
  # paragraph (`foo\` would be a literal backslash) is left out.
  test "hard breaks Markdown can't express degrade without corrupting the text" do
    heading = { "type" => "heading", "attrs" => { "level" => 2 }, "content" => [ text("a"), hard_break, text("b") ] }
    reloaded, = RichText::Document.from_markdown(RichText::Document.new("type" => "doc", "content" => [ heading ]).to_markdown)
    assert_equal [ heading.merge("content" => [ text("a b") ]) ], reloaded.to_h["content"]

    trailing = RichText::Document.new("type" => "doc", "content" => [ paragraph(text("a"), hard_break) ])
    reloaded, = RichText::Document.from_markdown(trailing.to_markdown)
    assert_equal [ paragraph(text("a")) ], reloaded.to_h["content"]
  end
end
