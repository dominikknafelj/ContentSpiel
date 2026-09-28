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
end
