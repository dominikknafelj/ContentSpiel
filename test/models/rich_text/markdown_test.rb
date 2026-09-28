require "test_helper"

class RichText::MarkdownTest < ActiveSupport::TestCase
  def round_trip(document) = RichText::Document.from_markdown(document.to_markdown).first.to_h

  test "every built-in round-trips" do
    page = create_page(title: "About")
    asset = nil # MediaAsset arrives in Task 4; the image case is added there
    document = RichText::Document.new("type" => "doc", "content" => [
      { "type" => "heading", "attrs" => { "level" => 2 }, "content" => [ { "type" => "text", "text" => "Hi" } ] },
      { "type" => "paragraph", "content" => [
        { "type" => "text", "text" => "b", "marks" => [ { "type" => "bold" } ] },
        { "type" => "text", "text" => " and " },
        { "type" => "text", "text" => "link", "marks" => [ { "type" => "internalLink", "attrs" => { "type" => "page", "id" => page.id } } ] } ] },
      { "type" => "orderedList", "attrs" => { "start" => 1 }, "content" => [ { "type" => "listItem", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "one" } ] } ] } ] },
      { "type" => "codeBlock", "attrs" => { "language" => "ruby" }, "content" => [ { "type" => "text", "text" => "puts 1" } ] },
      { "type" => "youtube", "attrs" => { "id" => "dQw4w9WgXcQ" } },
      { "type" => "horizontalRule" } ])
    assert_equal document.to_h, round_trip(document)
    assert_includes document.to_markdown, "::youtube{id=\"dQw4w9WgXcQ\"}"
    assert_includes document.to_markdown, "(cs:page/#{page.id})"
  end

  test "directive-looking text inside code stays code" do
    document, warnings = RichText::Document.from_markdown("```\n::youtube{id=\"dQw4w9WgXcQ\"}\n```\n")
    assert_equal "codeBlock", document.to_h["content"].first["type"]
    assert_empty warnings
  end

  test "unknown directives stay as text with a warning" do
    document, warnings = RichText::Document.from_markdown("::gallery{id=\"1\"}\n")
    assert_equal "paragraph", document.to_h["content"].first["type"]
    assert warnings.any? { |warning| warning.include?("gallery") }
  end

  # Literal text that merely *looks* like Markdown syntax -- an emphasis
  # marker, an ATX heading marker, or one of our own directive lines --
  # must escape on the way out and come back as the exact same plain text,
  # never reinterpreted as the syntax it resembles.
  test "text that looks like markdown syntax round-trips as literal text" do
    [ "*not bold*", "::youtube{id=\"dQw4w9WgXcQ\"}", "# not a heading" ].each do |literal|
      document = RichText::Document.new("type" => "doc", "content" => [
        { "type" => "paragraph", "content" => [ { "type" => "text", "text" => literal } ] } ])
      reloaded, warnings = RichText::Document.from_markdown(document.to_markdown)
      assert_equal document.to_h, reloaded.to_h, "expected #{literal.inspect} to round-trip literally"
      assert_empty warnings
    end
  end
end
