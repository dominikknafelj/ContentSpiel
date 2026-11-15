require "test_helper"

# The built-in's contains pass (search 2 spec §3.4): in Japanese, Chinese,
# Thai and Korean an entry is found by the text its title or body holds,
# every whitespace-separated part of the query, a typed `%` or `_` only
# itself; after the whole-run hits, never twice, never close.
class SiteSearch::Postgres::ContainsTest < ActiveSupport::TestCase
  setup do
    with_locales(Locales.enabled | %w[ja], default: Locales.default)
    @pages = 0
  end

  def query(text, language) = SiteSearch::Query.new(text: text, language: language, page: 1, per_page: 10, now: Time.current)

  def deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3

  def contains(text, language) = SiteSearch::Postgres::Contains.new(query(text, language), deadline: deadline, exclude: nil).results.hits

  # A live page titled `title` in `language`, with `body` there.
  def create_page_in(language, title:, body: nil)
    @pages += 1
    page = create_page(title: "Host #{@pages}", translations: { language => { title: title, slug: "host-#{@pages}" } })
    if body
      block = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }, translations: { language => { body: rich_doc(body) } })
      assert block.ok?, block.errors.to_sentence
      publish_changes(page)
    end
    page
  end

  # The hits of the whole query for `text`: a page whose title is the
  # whole run and one whose title only holds it, the whole run first.
  def contains_after_whole_run(text, language)
    whole = create_page_in(language, title: text)
    inside = create_page_in(language, title: "#{text}エンジン")
    hits = SiteSearch::Postgres::Query.new(query(text, language), deadline: deadline).results.hits
    assert_equal [ whole.id, inside.id ], hits.map(&:record_id)
    hits
  end

  def contains_snippet(body, part)
    create_page_in("ja", title: "本文", body: body)
    contains(part, "ja").sole.snippet
  end

  test "a typed % finds a percent sign, not everything" do
    with_percent = create_page_in("ja", title: "割引50%の案内")
    create_page_in("ja", title: "検索")
    assert_equal [ with_percent.id ], contains("%", "ja").map(&:record_id)
  end

  test "contains hits come after the whole-run hits, without duplicates, and are not close" do
    hits = contains_after_whole_run("検索", "ja")
    assert_equal hits.map(&:record_id).uniq, hits.map(&:record_id)
    refute hits.any?(&:close)
  end

  test "the snippet is cut around the first occurrence, 80 before and 300 in all, every part marked" do
    snippet = contains_snippet(("あ" * 200) + "検索" + ("い" * 400), "検索")
    assert_operator snippet.text.length, :<=, 300
    assert_equal [ [ 80, 2 ] ], snippet.marks
  end

  test "every part must be held, and every occurrence of each is marked" do
    page = create_page_in("ja", title: "案内", body: "検索の使い方。エンジンの検索")
    create_page_in("ja", title: "案内", body: "検索だけ")
    hits = contains("検索 エンジン", "ja")
    assert_equal [ page.id ], hits.map(&:record_id)
    snippet = hits.first.snippet
    assert_equal %w[検索 エンジン 検索], snippet.marks.map { |start, length| snippet.text[start, length] }
  end

  test "a title that holds the text comes before a body that does, and an earlier place in the body first" do
    late = create_page_in("ja", title: "案内", body: "あいうえお検索")
    early = create_page_in("ja", title: "案内", body: "検索あいうえお")
    titled = create_page_in("ja", title: "検索の案内")
    assert_equal [ titled.id, early.id, late.id ], contains("検索", "ja").map(&:record_id)
  end

  test "a page that is not live is not found" do
    create_page_in("ja", title: "検索の案内").then { |page| Pages::Save.call(page.reload, attributes: { published: false }) }
    assert_empty contains("検索", "ja")
  end

  test "the query's words are binds, never statement text" do
    create_page_in("ja", title: "検索の案内")
    statements = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { statements << payload[:sql] }, "sql.active_record") { contains("検索", "ja") }
    refute statements.any? { _1.include?("検索") }
  end

  test "the whole query pages the whole-run hits and the contains hits as one list, the total counting both" do
    create_page_in("ja", title: "検索")
    3.times { create_page_in("ja", title: "検索エンジン") }
    first = SiteSearch::Postgres::Query.new(query("検索", "ja").with(per_page: 2), deadline: deadline).results
    second = SiteSearch::Postgres::Query.new(query("検索", "ja").with(per_page: 2, page: 2), deadline: deadline).results
    assert_equal [ 4, 4 ], [ first.total, second.total ]
    assert_equal 4, (first.hits + second.hits).map(&:record_id).uniq.size
    assert_equal [ "skipped", "skipped" ], [ first.close_outcome, second.close_outcome ]
  end
end
