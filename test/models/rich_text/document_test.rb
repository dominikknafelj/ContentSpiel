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
end
