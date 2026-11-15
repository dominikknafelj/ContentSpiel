require "test_helper"

# The test backend obeys the contract every backend's test includes, and
# can be told to fail or to be slow, for the callers' tests.
class SiteSearch::FakeTest < ActiveSupport::TestCase
  include SiteSearchBackendContract
  include SiteSearchBackendContract::BareDocuments

  def backend = @backend ||= SiteSearch::Fake.new

  def deadline_in(seconds) = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds

  def query(text, close_matches: true) = SiteSearch::Query.new(text: text, language: "en", page: 1, per_page: 10, now: Time.current, close_matches: close_matches)

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

  # Close matches stand in for an outside engine's (spec §7.3): a word one
  # edit away (a letter changed, added, dropped, or two neighbours swapped)
  # when no document matches exactly, and a correction of each word that is
  # no word of the visible documents by its first close word.
  test "a typo finds close hits and a correction when nothing is exact" do
    guide = contract_document(title: "Deployment guide", body: "rolling out")
    backend.index([ guide, contract_document(title: "Harbour") ])

    results = backend.search(query("deploymnet guide"), deadline: deadline_in(1))

    assert_equal [ guide.key ], results.hits.map { |hit| hit_key(hit) }
    assert results.hits.all?(&:close)
    assert_equal 1, results.total
    assert_equal [ [ 0, 10 ] ], results.hits.first.snippet.marks.first(1)
    assert_equal "deployment guide", results.correction
  end

  test "an exact hit, or close_matches: false, answers no close hit and no correction" do
    backend.index([ contract_document(title: "Deployment guide"), contract_document(title: "Deploymnet notes") ])

    exact = backend.search(query("deploymnet"), deadline: deadline_in(1))
    assert_equal 1, exact.hits.size
    assert_not exact.hits.first.close
    assert_nil exact.correction

    backend.clear
    backend.index([ contract_document(title: "Deployment guide") ])
    strict = backend.search(query("deploymnet", close_matches: false), deadline: deadline_in(1))
    assert_empty strict.hits
    assert_nil strict.correction
  end

  test "a correction is built only from the words of documents in view and in the language" do
    backend.index([ contract_document(title: "Deployment", shown_from: 1.day.from_now), contract_document(title: "Deployment", language: "de") ])

    results = backend.search(query("deploymnet"), deadline: deadline_in(1))

    assert_empty results.hits
    assert_nil results.correction
  end

  test "a correction leaves out the code field's words, as the built-in's vocabulary does" do
    backend.index([ contract_document(title: "Notes", code: "kubectl apply") ])

    assert_nil backend.search(query("kubectk"), deadline: deadline_in(1)).correction
  end

    test "answer_with, answer_for and asked, for the callers' tests" do
    fake = SiteSearch::Fake.new
    everything = SiteSearch::Results.new(hits: [], total: 7)
    albatross = SiteSearch::Results.new(hits: [], total: 1)
    fake.answer_with(everything)
    fake.answer_for("albatross", albatross)

    assert_same albatross, fake.search(query("albatross"), deadline: deadline_in(1))
    assert_same everything, fake.search(query("pelican"), deadline: deadline_in(1))
    assert_equal %w[albatross pelican], fake.asked.map(&:text)
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
