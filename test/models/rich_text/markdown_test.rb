require "test_helper"

class RichText::MarkdownTest < ActiveSupport::TestCase
  # Only `test "a plugin node's own directive round-trips ..."` below
  # actually registers anything extra, but restoring the schema after
  # every test in this class (not just that one) is the same cheap,
  # always-safe convention `RichText::SchemaTest` itself uses.
  teardown { Rails.application.reloader.prepare! }

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

  # Fix round 1 (C1): 5000 levels of `"> "` nested a `SystemStackError` up
  # out of `.from_markdown` before the Loader capped its own recursion --
  # not a `StandardError`, so `#load`'s own `rescue` alone never caught it.
  # This exact input is what the reviewer's runner probe reproduced it with.
  test "extremely deep nesting doesn't overflow the stack" do
    document, warnings = RichText::Document.from_markdown(("> " * 5000) + "hi\n")
    assert_empty document.validate
    assert warnings.any? { |warning| warning.include?("depth") }
  end

  # Fix round 1 (C2): 600 levels doesn't overflow the stack (well within
  # what Ruby's own call stack tolerates), so the pre-fix Loader happily
  # built a 600-deep document -- which then failed `RichText::Document
  # #validate` (`MAX_DEPTH` is 50) with no warning at all explaining why an
  # MCP write came back invalid. The Loader now caps its own recursion at
  # the same `MAX_DEPTH`, so the reloaded document is shallow enough to
  # validate, with a warning recorded for the content it had to drop.
  test "nesting past the maximum depth validates and warns instead of silently exceeding it" do
    document, warnings = RichText::Document.from_markdown(("> " * 600) + "hi\n")
    assert_empty document.validate
    assert_not_empty warnings
  end

  # Fix round 1 (I3): a `code` mark's content containing its own backtick
  # needs a longer fence (CommonMark spec §6.5), not the fixed single
  # backtick every other delimiter-wrapped mark can get away with -- a
  # literal single backtick around `` a`b `` would either close the span
  # early or fail to parse as one at all.
  test "a code mark on text containing a backtick round-trips exactly" do
    document = RichText::Document.new("type" => "doc", "content" => [
      { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "a`b", "marks" => [ { "type" => "code" } ] } ] } ])
    assert_equal document.to_h, round_trip(document)
  end

  # Fix round 1 (I4): `&copy;`, `&amp;` and `&#65;` are HTML/numeric
  # character entities CommonMark decodes wherever they appear in a text
  # run, with nothing to tell "the editor typed a literal ampersand" apart
  # from "this was meant as an entity" once it's plain text -- `to_markdown`
  # backslash-escapes every `&` so none of the three get decoded on reload.
  test "ampersand-led text that looks like an HTML entity round-trips literally" do
    [ "&copy; 2026", "Ben & Jerry's", "&amp;", "&#65;" ].each do |literal|
      document = RichText::Document.new("type" => "doc", "content" => [
        { "type" => "paragraph", "content" => [ { "type" => "text", "text" => literal } ] } ])
      assert_equal document.to_h, round_trip(document), "expected #{literal.inspect} to round-trip literally"
    end
  end

  # Fix round 1 (I5): this schema has no tabular node type at all, so a
  # Markdown table can only ever degrade -- enabling the `table` extension
  # (rather than leaving it off, which silently parsed table syntax as
  # meaningless paragraphs of literal pipe characters with no warning at
  # all) is what lets the Loader actually recognize a table and say so.
  test "a table degrades to one paragraph per row, with a warning" do
    markdown = <<~MARKDOWN
      | a | b |
      |---|---|
      | 1 | 2 |
    MARKDOWN
    document, warnings = RichText::Document.from_markdown(markdown)
    paragraphs = document.to_h["content"]

    assert_equal 2, paragraphs.size
    assert_equal [ "paragraph", "paragraph" ], paragraphs.map { |node| node["type"] }
    assert_includes paragraphs.first["content"].first["text"], "a"
    assert_includes paragraphs.first["content"].first["text"], "b"
    assert warnings.any? { |warning| warning.include?("table") }
  end

  # Fix round 1 (I6): directive dispatch is schema-driven
  # (`RichText::Schema.directive_node`/`TypeDefinition#directive`'s
  # attribute mapping), not a hardcoded `case name when "youtube" ...`, so
  # a plugin's own directive node type round-trips exactly the way a
  # built-in's does -- proven here with a throwaway type this test
  # registers itself, restored by this class's own `teardown`.
  test "a plugin node's own directive round-trips through the schema, not a hardcoded case" do
    RichText::Schema.register_node("test/widget") do |node|
      node.attribute :size, :integer, required: true
      node.directive "widget", size: :integer
      node.html { |n, children, ctx| "" }
      node.markdown_out { |n, children, ctx| node.directive_markdown(n) }
    end

    document = RichText::Document.new("type" => "doc", "content" => [ { "type" => "test/widget", "attrs" => { "size" => 3 } } ])
    markdown = document.to_markdown
    assert_includes markdown, %(::widget{size="3"})

    reloaded, warnings = RichText::Document.from_markdown(markdown)
    assert_equal document.to_h, reloaded.to_h
    assert_empty warnings
  end

  # Fix round 1 (I7): `[italic, bold]` and `[bold, italic]` both dump to
  # `***hey***`-shaped Markdown (indistinguishable from each other once
  # parsed) and so can only ever reload as one of the two -- the canonical,
  # schema-registration order (`RichText::Document#normalized`'s own
  # comment) every editor-built document already uses. Round-trip
  # exactness is defined over that canonical form, not the raw input.
  test "marks canonicalize to schema registration order regardless of input order" do
    reversed = RichText::Document.new("type" => "doc", "content" => [
      { "type" => "paragraph", "content" => [
        { "type" => "text", "text" => "hey", "marks" => [ { "type" => "italic" }, { "type" => "bold" } ] } ] } ])
    canonical = RichText::Document.new("type" => "doc", "content" => [
      { "type" => "paragraph", "content" => [
        { "type" => "text", "text" => "hey", "marks" => [ { "type" => "bold" }, { "type" => "italic" } ] } ] } ])

    reloaded, warnings = RichText::Document.from_markdown(reversed.to_markdown)
    assert_equal canonical.to_h, reversed.normalized.to_h
    assert_equal canonical.to_h, reloaded.to_h
    assert_empty warnings
  end
end
