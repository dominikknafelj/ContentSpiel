require "test_helper"

# The test backend obeys the contract every backend's test includes, and
# can be told to fail or to be slow, for the callers' tests.
class SiteSearch::FakeTest < ActiveSupport::TestCase
  include SiteSearchBackendContract
  include SiteSearchBackendContract::BareDocuments

  def backend = @backend ||= SiteSearch::Fake.new

  def deadline_in(seconds) = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds

  def query(text) = SiteSearch::Query.new(text: text, language: "en", page: 1, per_page: 10, now: Time.current)

  test "raise_with raises from search and health" do
    fake = SiteSearch::Fake.new(raise_with: RuntimeError.new("engine down"))
    assert_equal "engine down", assert_raises(RuntimeError) { fake.search(query("a"), deadline: deadline_in(1)) }.message
    assert_raises(RuntimeError) { fake.health(deadline: deadline_in(1)) }
  end

  test "sleep_for past the deadline raises at the deadline" do
    fake = SiteSearch::Fake.new(sleep_for: 5)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(Timeout::Error) { fake.search(query("a"), deadline: start + 0.1) }
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - start, :<, 1
  end

  # The fake's snippet is what the callers' tests draw, so its marks must
  # stand on the words of its own text: a word inside another ("art" in
  # "Cartography") is no match, and a character whose downcase is longer
  # ("İ", two characters downcased) must not shift the marks.
  test "the snippet starts at the first whole word and marks the words of its own text" do
    long = "Cartography #{"plain " * 30}art and more art"
    backend.index([ contract_document(title: "Atlas", body: long), contract_document(title: "City", body: "İstanbul art fair") ])

    snippets = backend.search(query("art"), deadline: deadline_in(1)).hits.map(&:snippet)

    assert_equal 2, snippets.size
    snippets.each do |snippet|
      assert_not_empty snippet.marks
      snippet.marks.each { |start, length| assert_equal "art", snippet.text[start, length] }
    end
    city = snippets.find { |snippet| snippet.text.start_with?("İstanbul") }
    assert_equal [ [ 9, 3 ] ], city.marks
  end

  # "İ" downcases to "i" and a combining dot, which is no letter of WORD: a
  # text downcased before it is split falls apart at the dot, so the words
  # are split first and downcased after, for matching and marking alike.
  test "a word whose downcase is longer is found and marked whole" do
    backend.index([ contract_document(title: "City", body: "İstanbul art fair") ])

    hits = backend.search(query("İstanbul"), deadline: deadline_in(1)).hits

    assert_equal 1, hits.size
    assert_equal [ [ 0, 8 ] ], hits.first.snippet.marks
    assert_empty backend.search(query("stanbul"), deadline: deadline_in(1)).hits, "the dot splits no word"
  end
end
