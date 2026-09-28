require "test_helper"

class RichText::DocumentTest < ActiveSupport::TestCase
  def doc(*content) = RichText::Document.new("type" => "doc", "content" => content)
  def para(text) = { "type" => "paragraph", "content" => [ { "type" => "text", "text" => text } ] }

  test "blank and digest" do
    assert RichText::Document.empty.blank?
    assert RichText::Document.new(nil).blank?
    assert_not doc(para("Hi")).blank?
    assert_equal doc(para("Hi")).digest, doc(para("Hi")).digest
    assert_not_equal doc(para("Hi")).digest, doc(para("Ho")).digest
  end

  test "a valid document has no errors" do
    heading = { "type" => "heading", "attrs" => { "level" => 2 }, "content" => [ { "type" => "text", "text" => "T" } ] }
    bold = { "type" => "text", "text" => "b", "marks" => [ { "type" => "bold" } ] }
    assert_empty doc(heading, { "type" => "paragraph", "content" => [ bold ] }).validate
  end

  test "unknown types, bad attributes and a wrong root are errors" do
    assert_includes RichText::Document.new("type" => "paragraph").validate.join, "doc"
    assert doc({ "type" => "marquee" }).validate.any? { |message| message.include?("marquee") }
    assert doc({ "type" => "heading", "attrs" => { "level" => 1 } }).validate.any? { |message| message.include?("level") }
    assert doc({ "type" => "youtube", "attrs" => { "id" => "not-valid" } }).validate.any? { |message| message.include?("youtube") }
    link = { "type" => "text", "text" => "x", "marks" => [ { "type" => "link", "attrs" => { "href" => "javascript:alert(1)" } } ] }
    assert doc({ "type" => "paragraph", "content" => [ link ] }).validate.any? { |message| message.include?("href") }
  end

  # `#validate` has to survive documents that were never anywhere near the
  # editor -- a hand-edited jsonb row, an MCP-authored Markdown document --
  # so every shape here is something a well-formed Tiptap document could
  # never actually contain, but the JSON column has no way to rule out.
  # Each assertion doubles as "and it didn't raise": if `#validate` raised,
  # the `assert` itself would never run and the test would error out rather
  # than fail cleanly.
  test "malformed shapes produce error messages instead of raising" do
    assert doc(42).validate.any? { |message| message.include?("not an object") }
    assert doc(nil).validate.any? { |message| message.include?("not an object") }

    assert RichText::Document.new("type" => "doc", "content" => { "type" => "paragraph" }).validate.any? { |message| message.include?("content") && message.include?("array") }

    marks_as_hash = { "type" => "text", "text" => "x", "marks" => { "type" => "bold" } }
    assert doc({ "type" => "paragraph", "content" => [ marks_as_hash ] }).validate.any? { |message| message.include?("marks") && message.include?("array") }

    not_a_string = { "type" => "text", "text" => 42 }
    assert doc({ "type" => "paragraph", "content" => [ not_a_string ] }).validate.any? { |message| message.include?("text") }
  end

  test "nesting deeper than the maximum depth is an error, not a SystemStackError" do
    node = { "type" => "text", "text" => "x" }
    500.times { node = { "type" => "blockquote", "content" => [ node ] } }

    errors = doc(node).validate
    assert errors.any? { |message| message.include?("maximum nesting depth") }
  end

  # Fix round 1's addendum: `#digest`'s `payload.keys.sort` raises
  # `ArgumentError` the instant one Hash in the tree mixes a String and a
  # Symbol key (`<=>` isn't defined between them), which would make
  # `#to_html` raise too, since it computes `#digest` for its cache key --
  # and a Symbol *value* sitting where a String was expected would fail
  # every `==` comparison silently instead. Construction now stringifies
  # both, so a Symbol-keyed document and its String-keyed twin are simply
  # the same document.
  test "construction stringifies symbol keys and values so mixed-key documents don't raise" do
    symbol_keyed = RichText::Document.new(type: "doc", content: [ { type: "paragraph", content: [ { type: "text", text: "hi" } ] } ])
    string_keyed = RichText::Document.new("type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "hi" } ] } ])

    assert_equal string_keyed.to_h, symbol_keyed.to_h
    assert_equal string_keyed.digest, symbol_keyed.digest
    assert_kind_of String, symbol_keyed.to_html(locale: "en", urls: PublicSite::Urls.new)
  end

  # Same addendum: the stringify walk has to be exactly as depth-safe as
  # `#write_canonical`'s own iterative walk (this class's own regression
  # test above uses 500; this uses 5000, comfortably past it) -- a
  # recursive implementation would overflow the stack building this Hash
  # in the first place, before `RichText::Document.new` ever got a chance
  # to run.
  test "construction survives a pathologically deep, symbol-keyed document without raising" do
    node = { type: "text", text: "x" }
    5000.times { node = { type: "blockquote", content: [ node ] } }

    document = RichText::Document.new(type: "doc", content: [ node ])
    assert_kind_of String, document.digest
  end

  # Fix round 1's I7: an editor-built document already keeps its marks in
  # schema registration order (what ProseMirror itself stores), so
  # `#normalized` is a no-op for one -- this is really a regression test
  # for `#normalized` *not* reordering (or otherwise altering) a document
  # that was already canonical, complementing `RichText::MarkdownTest`'s
  # own coverage of the actually-reordering case.
  test "normalized is a no-op for a document whose marks are already in schema order" do
    document = doc({ "type" => "paragraph", "content" => [
      { "type" => "text", "text" => "hey", "marks" => [ { "type" => "bold" }, { "type" => "italic" } ] } ] })
    assert_equal document.to_h, document.normalized.to_h
  end

  # Task 7 fix round 1 (I2): existence checks only block references that
  # are new relative to `known_references`.
  test "validate skips existence checks for known references, but not new ones" do
    dead_link = { "type" => "text", "text" => "x", "marks" => [ { "type" => "internalLink", "attrs" => { "type" => "page", "id" => 999_999 } } ] }
    dead_image = { "type" => "image", "attrs" => { "asset_id" => 888_888, "alt" => "", "caption" => "" } }
    document = doc({ "type" => "paragraph", "content" => [ dead_link ] }, dead_image)

    assert_equal 2, document.validate.size
    assert_equal Set.new([ [ "internalLink", "id", 999_999, "page" ], [ "image", "asset_id", 888_888 ] ]), document.references
    assert_empty document.validate(known_references: document.references)

    # The same id under the other `type` is a different reference.
    other = doc({ "type" => "paragraph", "content" => [ dead_link.deep_merge("marks" => [ { "type" => "internalLink", "attrs" => { "type" => "post", "id" => 999_999 } } ]) ] })
    assert_equal [ "internalLink.id is invalid" ], other.validate(known_references: document.references)
  end

  test "known references never excuse a malformed attribute" do
    bad = doc({ "type" => "image", "attrs" => { "asset_id" => "42", "alt" => "", "caption" => "" } })
    assert_equal [ "image.asset_id must be a integer" ], bad.validate(known_references: Set.new([ [ "image", "asset_id", "42" ] ]))
  end

  test "references tolerates malformed shapes" do
    document = RichText::Document.new("type" => "doc", "content" => [ nil, "x", { "type" => "image", "attrs" => "nope" },
      { "type" => "text", "text" => "t", "marks" => [ nil, { "type" => "internalLink" } ] } ])
    assert_empty document.references
  end

  # Final fix wave (A): the content model Tiptap/ProseMirror itself enforces
  # (`content`/`marks`/`excludes` in the vendored extensions, checked by
  # `enableContentCheck`) is part of `#validate` too. A document that
  # passes here but that the editor refuses opens read-only in CS Studio --
  # which is exactly what an MCP-written body used to do.
  def text(value, *marks) = { "type" => "text", "text" => value }.merge(marks.empty? ? {} : { "marks" => marks.map { |mark| mark.is_a?(Hash) ? mark : { "type" => mark } } })
  def paragraph(*content) = { "type" => "paragraph", "content" => content }
  def link(href = "https://example.com") = { "type" => "link", "attrs" => { "href" => href } }

  test "code can't be combined with any other mark" do
    assert_empty doc(paragraph(text("x", "code"))).validate
    [ %w[bold code], [ "code", link ], %w[code italic] ].each do |marks|
      errors = doc(paragraph(text("x", *marks))).validate
      assert errors.any? { |message| message.include?("can't be combined") }, "expected #{marks.inspect} to be refused, got #{errors.inspect}"
    end
  end

  test "a mark type can't appear twice, and link and internalLink exclude each other" do
    page = create_page(title: "Target")
    internal = { "type" => "internalLink", "attrs" => { "type" => "page", "id" => page.id } }
    assert doc(paragraph(text("x", "bold", "bold"))).validate.any? { |message| message.include?("more than once") }
    assert doc(paragraph(text("x", link, internal))).validate.any? { |message| message.include?("can't be combined") }
    assert doc(paragraph(text("x", internal, internal))).validate.any? { |message| message.include?("more than once") }
    assert_empty doc(paragraph(text("x", "bold", "italic", "strike", link))).validate
  end

  test "text nodes can't be empty" do
    assert doc(paragraph(text(""))).validate.any? { |message| message.include?("empty") }
  end

  test "container content follows the editor's content expressions" do
    empty_paragraph = { "type" => "paragraph", "content" => [] }
    item = ->(*content) { { "type" => "listItem", "content" => content } }
    youtube = { "type" => "youtube", "attrs" => { "id" => "dQw4w9WgXcQ" } }

    valid = [
      doc,
      doc(empty_paragraph),
      doc({ "type" => "paragraph" }),
      doc({ "type" => "bulletList", "content" => [ item.(paragraph(text("a")), youtube) ] }),
      doc({ "type" => "blockquote", "content" => [ youtube ] }),
      doc({ "type" => "codeBlock" }),
      doc({ "type" => "codeBlock", "content" => [ text("x = 1") ] }),
      doc(paragraph(text("a"), { "type" => "hardBreak" }, text("b")))
    ]
    valid.each { |document| assert_empty document.validate, document.to_h.inspect }

    invalid = [
      doc({ "type" => "blockquote", "content" => [] }),
      doc({ "type" => "bulletList", "content" => [] }),
      doc({ "type" => "orderedList", "attrs" => { "start" => 1 } }),
      doc({ "type" => "bulletList", "content" => [ item.() ] }),
      doc({ "type" => "bulletList", "content" => [ item.(youtube) ] }),
      doc({ "type" => "bulletList", "content" => [ paragraph(text("a")) ] }),
      doc(text("loose")),
      doc(paragraph(paragraph(text("a")))),
      doc({ "type" => "heading", "attrs" => { "level" => 2 }, "content" => [ youtube ] }),
      doc({ "type" => "codeBlock", "content" => [ { "type" => "hardBreak" } ] }),
      doc({ "type" => "codeBlock", "content" => [ text("x", "bold") ] }),
      doc({ "type" => "horizontalRule", "content" => [ paragraph(text("a")) ] }),
      doc(paragraph(text("a")).merge("marks" => [ { "type" => "bold" } ]))
    ]
    invalid.each { |document| assert_not_empty document.validate, "expected #{document.to_h.inspect} to be invalid" }
  end

  test "validate is total for a root that isn't an object" do
    [ 42, [], "doc", true ].each do |root|
      errors = RichText::Document.new(root).validate
      assert errors.any? { |message| message.include?("root") }, "expected an error for #{root.inspect}"
    end
    assert_nothing_raised { RichText::Document.new(42).normalized.to_h }
  end
end
