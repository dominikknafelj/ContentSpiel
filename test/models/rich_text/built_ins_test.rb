require "test_helper"

# `RichText::BuiltIns.safe_href?` (Task 7 fix round 1, I1): a scheme
# allowlist, not a URI syntax check -- the editor accepts IRIs (unicode
# hosts/paths, a raw `|`) and the server has to agree, or the save 422s.
class RichText::BuiltInsTest < ActiveSupport::TestCase
  test "http(s), mailto and relative hrefs are safe, including IRIs URI.parse rejects" do
    [
      "https://example.com", "http://example.com/a?b=c#d", "mailto:a@b.com", "/about", "about", "#top", "?q=1", "//cdn.example.com/x",
      "https://münchen.de", "https://example.com/über", "https://en.wikipedia.org/wiki/Straße", "https://example.com/a|b", "HTTPS://EXAMPLE.COM"
    ].each { |href| assert RichText::BuiltIns.safe_href?(href), href }
  end

  test "other schemes, including obfuscated ones, are refused" do
    [
      "javascript:alert(1)", "JavaScript:alert(1)", "javascript&#58;alert(1)", "&#x6A;avascript:alert(1)", "java\tscript:alert(1)",
      "java\nscript:alert(1)", " javascript:alert(1)", "data:text/html,x", "vbscript:x", "ftp://example.com", "", "   ", nil, 42
    ].each { |href| assert_not RichText::BuiltIns.safe_href?(href), href.inspect }
  end

  test "a document with a unicode link validates" do
    document = RichText::Document.new("type" => "doc", "content" => [ { "type" => "paragraph", "content" => [
      { "type" => "text", "text" => "x", "marks" => [ { "type" => "link", "attrs" => { "href" => "https://münchen.de/über" } } ] } ] } ])

    assert_empty document.validate
  end
end
