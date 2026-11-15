require "test_helper"

# The built-in's close pass (search 2 spec §3.3): for a plain query that
# found nothing, each query word of 4 or more characters that no entry a
# visitor sees now holds gets the 3 most similar words some entry in
# force holds, every word and candidate a bind; the close tsquery ORs each
# word with its candidates and ANDs the words; the correction takes each
# word's first candidate.
class SiteSearch::Postgres::CloseTest < ActiveSupport::TestCase
  def query(text, language: "en") = SiteSearch::Query.new(text: text, language: language, page: 1, per_page: 10, now: Time.current)

  def close(text, language: "en") = SiteSearch::Postgres::Close.new(query(text, language: language), deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3)

  # A live page titled by each word, so each is in the vocabulary and held
  # by an entry in force.
  def words!(locale, words)
    assert_equal "en", locale, "the pages are titled in the default language"
    words.each { |word| create_page(title: word) }
  end

  # The text of every statement the block sends.
  def captured_sql(&block)
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
    statements
  end

  test "a query with a quote, a word beginning with - or a standalone or is not plain" do
    [ %("a b"), "albatross -gull", "albatross or gull", "albatross OR gull" ].each { refute close(_1).plain?, _1 }
    assert close("albatross gull").plain?
    assert close("albatross orca").plain?, "or inside a word is no operator"
  end

  # Measured on Postgres 17: similarity to "deploymnet" is 0.615 for
  # deploymet and deploymnt (both 9 long, a tie broken alphabetically), 0.5
  # for deploymen (9 long) and deploy (6 long, a tie broken by the length
  # difference), and 0.158 for employment, under the threshold.
  test "candidates are the 3 most similar words at 0.3 or more, ties by length difference then alphabetically" do
    words!("en", %w[deploy deploymen deploymnt deploymet employment])
    assert_equal %w[deploymet deploymnt deploymen], close("deploymnet").candidates["deploymnet"]
  end

  test "a word a visible entry holds, or shorter than 4, is not corrected" do
    words!("en", %w[albatross])
    assert_empty close("albatross gul").candidates
  end

  test "a word only the vocabulary holds, with no entry a visitor sees now, is still corrected" do
    words!("en", %w[albatross])
    SiteSearch::Word.insert_all([ { locale: "en", word: "albatros" } ], unique_by: %i[locale word]) # version: none (a test puts a word in the vocabulary that no live entry holds)
    assert_equal [ "albatross" ], close("albatros").candidates["albatros"]
  end

  test "a word only a page that is not live holds is no candidate" do
    create_page(title: "Albatross", published: false)
    SiteSearch::Word.insert_all([ { locale: "en", word: "albatross" } ], unique_by: %i[locale word]) # version: none (a test puts a word in the vocabulary that no live entry holds)
    assert_empty close("albatros").candidates
  end

  test "the correction takes each word's first candidate and keeps the rest of the text" do
    words!("en", %w[deployment])
    assert_equal "Zero deployment", close("Zero deploymnet").correction
    assert_nil close("zero downtime").correction, "no word changed"
  end

  test "close hits are close and marked by the variant found" do
    page = create_page(title: "Zero-downtime deployment")
    block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }, translations: { "en" => { body: rich_doc("We plan every deployment.") } })
    assert block.ok?, block.errors.to_sentence
    publish_changes(page)
    found = close("deploymnet").results
    assert_equal [ page.id ], found.hits.map(&:record_id)
    assert found.hits.all?(&:close)
    assert_equal 1, found.total
    assert_equal "deployment", found.correction
    snippet = found.hits.first.snippet
    assert_equal [ "deployment" ], snippet.marks.map { |start, length| snippet.text[start, length] }
  end

  test "every word and candidate is a bind, never statement text" do
    words!("en", %w[deployment])
    sql = captured_sql { close("deploymnet'; DROP TABLE x; --").results }
    assert sql.any? { _1.include?("similarity") }, "the candidate lookup ran"
    refute sql.any? { _1.include?("DROP TABLE") || _1.include?("deploymnet") }
  end

  test "a query of stopwords and digits runs no candidate lookup and offers no correction" do
    assert_no_queries_match(/search_words/) { assert_nil close("the 2026 and").correction }
  end

  test "a stopword of four letters or more is no word to correct" do
    words!("en", %w[theme])
    assert_empty close("these").candidates
  end
end
