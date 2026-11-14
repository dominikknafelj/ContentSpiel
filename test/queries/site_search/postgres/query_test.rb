require "test_helper"

# The built-in backend's query (spec §6.3): only what a visitor sees now,
# by the clock in the query and never a job, ranked, cut into a page, with
# a snippet marked on the match and the visitor's words handed to the
# database as a bind.
class SiteSearch::Postgres::QueryTest < ActiveSupport::TestCase
  def backend = @backend ||= SiteSearch::Postgres.new

  def index(record)
    record = record.reload
    [ Publishing.current(record), Publishing.pending(record) ].compact.each do |copy|
      backend.index(SiteSearch::Documents.for(copy, now: Time.current))
    end
    record
  end

  def search(text, language: "en", page: 1, now: Time.current, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3)
    query = SiteSearch::Query.new(text: text, language: language, page: page, per_page: SiteSearch::Query::PER_PAGE, now: now)
    SiteSearch::Postgres::Query.new(query, deadline: deadline).results
  end

  def found(text, **options) = search(text, **options).hits.map { |hit| [ hit.record_type, hit.record_id ] }

  def body_page(title, body, parent: root_page)
    page = create_page(title: title, parent: parent)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "rich_text" }, translations: { "en" => { body: rich_doc(body) } })
    assert result.ok?, result.errors.to_sentence
    publish_changes(page)
  end

  # A published page that lists the blog's posts, which is what gives a post
  # its address.
  def listing
    page = create_page(title: "Blog", published: false)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert result.ok?, result.errors.to_sentence
    assert Pages::Save.call(page.reload, attributes: { published: true }).ok?
    page
  end

  test "only the copy in force of a kept, published, visible record with a current address is found" do
    listing
    draft = create_page(title: "Albatross draft", published: false)
    trashed = index(create_page(title: "Albatross trashed"))
    assert Trash::Move.call(trashed).ok?
    hidden_parent = create_page(title: "Hidden parent", published: false)
    under_draft = index(create_page(title: "Albatross below", parent: hidden_parent))
    unaddressed = index(create_page(title: "Albatross unaddressed"))
    PublicPath.where(record_type: "Page", record_id: unaddressed.id, locale: "en").delete_all # version: none (a test takes an address away)
    post = index(create_post(title: "Albatross post"))

    assert_equal [ [ "Post", post.id ] ], found("albatross")
    assert_equal 1, search("albatross").total

    assert Pages::Save.call(draft.reload, attributes: { published: true }).ok?
    index(draft)
    assert Trash::Restore.call(trashed.reload).ok?
    assert Pages::Save.call(hidden_parent.reload, attributes: { published: true }).ok?
    PublicSite::Paths.rebuild!

    expected = [ [ "Page", draft.id ], [ "Page", trashed.id ], [ "Page", under_draft.id ], [ "Page", unaddressed.id ], [ "Post", post.id ] ]
    assert_equal expected.sort, found("albatross").sort
    assert_equal 5, search("albatross").total
  end

  test "a post under a page that is not published is not found" do
    blog = listing
    post = index(create_post(title: "Albatross post"))
    assert_equal blog.id, PublicPath.find_by!(record_type: "Post", record_id: post.id, locale: "en", current: true).listed_on_id
    assert_equal [ [ "Post", post.id ] ], found("albatross")

    Page.where(id: blog.id).update_all(published_at: nil) # version: none (a test hides the listing page around the services)

    assert_empty found("albatross")
  end

  test "a scheduled change is found by its old words before its time and by its new words after it" do
    page = create_page(title: "Albatross")
    assert Pages::Save.call(page, translations: { "en" => { title: "Pelican" } }).ok?
    live_at = 1.day.from_now.change(usec: 0)
    publish_changes(page, at: live_at)
    index(page)
    old, pending = Publishing.current(page), Publishing.pending(page)

    assert_equal [ old.id ], search("albatross").hits.map(&:copy_id)
    assert_empty found("pelican")

    travel_to(live_at + 1.second) do
      assert_empty found("albatross")
      assert_equal [ pending.id ], search("pelican").hits.map(&:copy_id)
    end
  end

  test "a page of ten, ordered by rank then type and id, with the total" do
    strong = 3.times.map { |index| index(create_page(title: "Albatross #{%w[one two three][index]}")) }
    weak = 9.times.map { |index| index(body_page("Plain #{index}", "An albatross flies by.")) }

    first = search("albatross")
    second = search("albatross", page: 2)

    assert_equal [ 10, 2 ], [ first.hits.size, second.hits.size ]
    assert_equal [ 12, 12 ], [ first.total, second.total ]
    assert_equal strong.map(&:id).sort, first.hits.first(3).map(&:record_id)
    assert_equal weak.map(&:id).sort, (first.hits.drop(3) + second.hits).map(&:record_id)
    ranks = (first.hits + second.hits).map(&:rank)
    assert_equal ranks.sort.reverse, ranks
    assert_empty search("albatross", page: 3).hits
  end

  test "websearch syntax alone and stop words find nothing and raise nothing" do
    index(body_page("The or", "Or the unclosed thing."))

    [ '"unclosed', "-", "or", "the", '""' ].each do |text|
      results = search(text)
      expected = text == '"unclosed' ? 1 : 0
      assert_equal expected, results.total, text
    end
    [ "-", "or", "the", '""' ].each do |text|
      assert_equal SiteSearch::Results.new(hits: [], total: 0), search(text), text
    end
  end

  test "the snippet's marks are on the matched words and its text has no marker" do
    index(body_page("Shore", "Bread & butter: along the shore a lighthouse stands, and the lighthouses guide the boats home."))

    snippet = search("lighthouse").hits.first.snippet

    assert_no_match(/[\u{E000}\u{E001}]/, snippet.text)
    assert_includes snippet.text, "Bread & butter", "the text is plain, never escaped"
    assert_equal [ "lighthouse", "lighthouses" ], snippet.marks.map { |(start, length)| snippet.text[start, length] }
  end

  test "the query text reaches the database as a bind named q" do
    index(create_page(title: "Albatross"))
    statements = []
    callback = ->(*, payload) { statements << payload unless payload[:name] == "SCHEMA" }

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { assert_equal 1, search("albatross").total }

    asking = statements.select { |payload| payload[:sql].include?("websearch_to_tsquery") }
    assert_equal 2, asking.size, "the page and the total"
    asking.each do |payload|
      assert_not_includes payload[:sql], "albatross"
      assert payload[:binds].any? { |bind| bind.is_a?(ActiveRecord::Relation::QueryAttribute) && bind.name == "q" }
    end
    assert statements.none? { |payload| payload[:sql].include?("albatross") }
  end

  test "a statement past the deadline raises" do
    index(create_page(title: "Albatross"))

    statements = []
    callback = ->(*, payload) { statements << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      assert_raises(ActiveRecord::QueryCanceled) { search("albatross", deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1) }
    end
    assert_empty statements, "no time left: the database is not asked"
  end

  test "the statement timeout is the time left, and never under a millisecond" do
    assert_equal 2500, SiteSearch::Postgres::Query.timeout_in_ms(2.5)
    assert_equal 1, SiteSearch::Postgres::Query.timeout_in_ms(0.0004), "0 would be no timeout at all"
    assert_nil SiteSearch::Postgres::Query.timeout_in_ms(0)
    assert_nil SiteSearch::Postgres::Query.timeout_in_ms(-1)
  end

  test "the statement timeout is set inside the query's own transaction and goes with it" do
    index(create_page(title: "Albatross"))
    statements = capture_sql { search("albatross") }

    assert statements.any? { |sql| sql.match?(/\ASET LOCAL statement_timeout = \d+\z/) }
    assert_not_equal "1ms", ActiveRecord::Base.connection.select_value("SHOW statement_timeout")
    before = ActiveRecord::Base.connection.select_value("SHOW statement_timeout")
    search("albatross", deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.25)
    assert_equal before, ActiveRecord::Base.connection.select_value("SHOW statement_timeout")
  end
end
