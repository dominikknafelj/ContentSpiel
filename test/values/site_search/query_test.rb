require "test_helper"

# What a visitor typed, as every backend is handed it (spec §5.1, §8.3).
class SiteSearch::QueryTest < ActiveSupport::TestCase
  test "normalise strips, collapses whitespace and answers nil for blank or a non-String" do
    assert_equal "a b", SiteSearch::Query.normalise("  a \n b ")
    assert_equal "a b", SiteSearch::Query.normalise("a\tb")
    assert_nil SiteSearch::Query.normalise([ "a" ])
    assert_nil SiteSearch::Query.normalise({ "x" => "1" })
    assert_nil SiteSearch::Query.normalise(nil)
    assert_nil SiteSearch::Query.normalise("   ")
    assert_nil SiteSearch::Query.normalise("\u0000\u{E000}")
  end

  # The snippet's markers (U+E000, U+E001, spec §6.4) typed into a query
  # would land in the marked text; a NUL or an invalid byte would make the
  # database refuse the statement.
  test "normalise takes out control and marker characters and invalid bytes" do
    assert_equal "abc", SiteSearch::Query.normalise("a\u0000b\u{E000}c\xFF".dup.force_encoding("UTF-8"))
    assert_equal "ab", SiteSearch::Query.normalise("a\u{E001}b\u0007")
    assert_predicate SiteSearch::Query.normalise("a\xFFb".b), :valid_encoding?
  end

  # A bidi override echoed in "Nothing found for …" would make the site's
  # own sentence read as other text; the joiners stay, since a word of
  # Persian or Hindi and an emoji sequence are written with them.
  test "normalise takes out the bidi controls and zero-width spaces, and keeps the joiners" do
    assert_equal "abcdefg", SiteSearch::Query.normalise("a\u202Eb\u2066c\u200Fd\u200Be\uFEFFf\u061Cg")
    assert_equal "\u0645\u06CC\u200C\u062E\u0648\u0627\u0647\u0645 \u{1F469}\u200D\u{1F4BB}", SiteSearch::Query.normalise("\u0645\u06CC\u200C\u062E\u0648\u0627\u0647\u0645 \u{1F469}\u200D\u{1F4BB}")
  end

  test "normalise keeps a long query whole: the length is judged after it" do
    text = "a" * (SiteSearch::Query::MAX_LENGTH + 1)
    assert_equal text, SiteSearch::Query.normalise(text)
  end

  test "offset is the page's first index" do
    query = ->(page, per_page = SiteSearch::Query::PER_PAGE) { SiteSearch::Query.new(text: "a", language: "en", page:, per_page:, now: Time.current) }
    assert_equal 0, query.(1).offset
    assert_equal 10, query.(2).offset
    assert_equal 6, query.(4, 2).offset
  end
end
