require "test_helper"

# The built-in's title suggestions (search 2 spec §4.3): the titles a
# visitor sees now whose words begin with each word of the prefix, by
# `simple` words and a prefix tsquery built from letters, marks and digits
# alone; in a `LIMITED` language, the titles that contain the text.
class SiteSearch::Postgres::SuggestTest < ActiveSupport::TestCase
  def deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3

  def suggest_query(text, language: "en", limit: SiteSearch::SUGGEST_LIMIT)
    SiteSearch::SuggestQuery.new(text: text, language: language, now: Time.current, limit: limit)
  end

  def suggest_ids(text, language: "en", limit: SiteSearch::SUGGEST_LIMIT)
    SiteSearch::Postgres.new.suggest(suggest_query(text, language: language, limit: limit), deadline: deadline).items.map(&:record_id)
  end

  def publish(page) = page

  def enable_locale(code) = with_locales(Locales.enabled | [ code ], default: Locales.default)

  test "a prefix of tsquery syntax suggests by its letters only" do
    assert_equal "'albatross':* & 'gul':*", SiteSearch::Postgres::Suggest.tsquery_text("albatross:* & !gul|")
    assert_nil SiteSearch::Postgres::Suggest.tsquery_text("&|!:*()")
    assert_equal "'über':* & 'café':*", SiteSearch::Postgres::Suggest.tsquery_text("Über 'café'"), "lowercased, quotes taken out"
  end

  test "a title that begins with the prefix comes first, then shorter titles" do
    ids = [ "A deployment guide", "Deployments", "Deployment" ].map { publish(create_page(title: _1)).id }
    assert_equal ids.values_at(2, 1, 0), suggest_ids("deploym")
  end

  test "every word of the prefix begins a word of the title, and the limit holds" do
    zero = create_page(title: "Zero-downtime deployments")
    create_page(title: "Deployments at night")
    assert_equal [ zero.id ], suggest_ids("zero deploym")
    assert_equal 1, suggest_ids("deploym", limit: 1).size
    assert_empty suggest_ids("ployments"), "a word's middle is no prefix"
  end

  test "a limited language suggests a title that contains the text" do
    enable_locale("ja")
    page = publish(create_page(title: "Host", translations: { "ja" => { title: "検索エンジン", slug: "kensaku" } }))
    assert_equal [ page.id ], suggest_ids("エンジン", language: "ja")
    assert_empty suggest_ids("%", language: "ja"), "a typed % is only itself"
  end

  test "a draft's title and another language's are not suggested" do
    create_page(title: "Albatross draft", published: false)
    create_page(title: "Host", translations: { "de" => { title: "Albatros", slug: "albatros" } })
    assert_empty suggest_ids("alba")
  end

  test "syntax alone asks the database nothing" do
    statements = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { statements << payload[:sql] }, "sql.active_record") do
      assert_empty suggest_ids("&|!:*()")
    end
    assert_empty statements
  end

  test "the prefix is a bind, never statement text, and one statement answers" do
    create_page(title: "Zanzibar")
    statements = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { statements << payload[:sql] unless payload[:name] == "TRANSACTION" }, "sql.active_record") do
      assert_equal 1, suggest_ids("zanzib").size
    end
    refute statements.any? { _1.downcase.include?("zanzib") }
    assert_equal 1, statements.count { _1.start_with?("SELECT") }
  end

  test "the title match is the expression index's" do
    plan = SiteSearch::Entry.transaction do
      SiteSearch::Entry.connection.execute("SET LOCAL enable_seqscan = off") # sql: a test's planner setting; no Arel node for SET
      SiteSearch::Entry.where(SiteSearch::Postgres::Suggest.new(suggest_query("deploym"), deadline: deadline).send(:title_match)).explain.inspect
    end
    assert_includes plan, "index_search_entries_on_title_words"
  end

  test "a deadline already passed asks the database nothing and raises" do
    statements = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { statements << payload[:sql] unless payload[:name] == "TRANSACTION" }, "sql.active_record") do
      assert_raises(ActiveRecord::QueryCanceled) do
        SiteSearch::Postgres.new.suggest(suggest_query("deploym"), deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1)
      end
    end
    assert_empty statements
  end
end
