require "test_helper"

# Every hit is checked again before it is drawn (spec §5.6): an outside
# index can be stale, so `SiteSearch::Shown` keeps a hit only when its record
# is kept, published and visible, has a current address in the language and
# the hit's copy is the record's copy in force, and reads what is drawn from
# that copy and `public_paths`, never from the engine.
class SiteSearch::ShownTest < ActiveSupport::TestCase
  def fake = @fake ||= SiteSearch::Fake.new

  # The record's copy in force, handed to the fake as it is now.
  def index(record)
    record = record.reload
    fake.index(SiteSearch::Documents.for(Publishing.current(record), now: Time.current))
    record
  end

  def query(text, now: Time.current) = SiteSearch::Query.new(text: text, language: "en", page: 1, per_page: 10, now: now)

  def results(text) = fake.search(query(text), deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3)

  def shown(text, now: Time.current) = SiteSearch::Shown.for(results(text), locale: "en", now: now)

  # The item drawn for `record` in a search for "albatross".
  def shown_item_of(record) = shown("albatross").find { |item| item.record.id == record.id && item.record.class == record.class }

  # What `SiteSearch::Shown.for` costs, whatever the number of hits, a
  # post's tags read included (`test "ten hits cost a constant number of
  # statements"`): a statement added is a decision, not a drift.
  SHOWN_STATEMENTS = 16

  def listing
    page = create_page(title: "Blog", published: false)
    result = ContentBlocks::Save.call(ContentBlock.new(owner: page), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } })
    assert result.ok?, result.errors.to_sentence
    assert Pages::Save.call(page.reload, attributes: { published: true }).ok?
    page
  end

  test "a hit for a record trashed, unpublished, moved under a draft page or superseded since it was indexed is not drawn" do
    trashed = index(create_page(title: "Albatross trashed"))
    unpublished = index(create_page(title: "Albatross unpublished"))
    moved = index(create_page(title: "Albatross moved"))
    superseded = index(create_page(title: "Albatross superseded"))
    draft = create_page(title: "Draft section", published: false)
    assert_equal 4, results("albatross").hits.size
    assert_equal 4, shown("albatross").size, "each is drawn while it is as indexed"

    assert Trash::Move.call(trashed.reload).ok?
    assert Pages::Save.call(unpublished.reload, attributes: { published: false }).ok?
    assert Pages::Move.call(moved.reload, parent: draft, position: 0).ok?
    assert Pages::Save.call(superseded.reload, translations: { "en" => { title: "Albatross superseded again" } }).ok?
    publish_changes(superseded)

    assert_equal 4, results("albatross").hits.size, "the index is stale: it holds all four as they were"
    assert_empty shown("albatross")
  end

  test "a hit whose record has no address in the language is not drawn" do
    page = index(create_page(title: "Albatross"))
    PublicPath.where(record_type: "Page", record_id: page.id, locale: "en").delete_all # version: none (a test takes an address away)

    assert_empty shown("albatross")
  end

  test "a hit for a record scheduled to go live is not drawn before its time" do
    page = index(create_page(title: "Albatross"))
    Page.where(id: page.id).update_all(published_at: 1.day.from_now) # version: none (a test schedules the record around the services)

    assert_empty shown("albatross")
  end

  test "a hit whose record was purged since it was indexed is not drawn" do
    page = index(create_page(title: "Albatross"))
    assert delete_for_good(page.reload)

    assert_equal 1, results("albatross").hits.size, "the index is stale: it holds the purged page"
    assert_equal [], shown("albatross")
  end

  # A visitor's search asks at the request's moment, and the rule that a
  # post's listing page is live is asked at that moment too, not at the
  # clock's when the check runs.
  test "a post is judged live at the moment asked" do
    listing
    post = index(create_post(title: "Albatross sighting"))
    Post.where(id: post.id).update_all(published_at: 1.day.from_now) # version: none (a test schedules the record around the services)
    later = 2.days.from_now

    assert_empty shown("albatross")
    assert_equal [ post.id ], shown("albatross", now: later).map { |item| item.record.id }
  end

  test "title, address and date come from the copy in force and public_paths, never the engine" do
    listing
    parent = create_page(title: "Seabirds")
    page = index(create_page(title: "Albatross", parent: parent))
    post = index(create_post(title: "Albatross sighting"))
    stale = fake.documents.values.find { |document| document.record_id == page.id && document.record_type == "Page" }
    fake.index([ stale.with(url: "/somewhere-old") ])
    assert Pages::Save.call(page.reload, translations: { "en" => { slug: "great-albatross" } }).ok?
    assert Pages::Save.call(parent.reload, translations: { "en" => { title: "Seabirds, renamed in the rows" } }).ok?

    items = shown("albatross").index_by(&:kind)

    assert_equal "/seabirds/great-albatross", items[:page].url_path
    assert_equal "Albatross", items[:page].title
    assert_equal [ "Home", "Seabirds" ], items[:page].where, "the ancestors' titles as published, not as in the rows"
    assert_nil items[:page].date
    assert_equal page.id, items[:page].record.id
    assert items[:page].record.readonly?, "the published view"

    assert_equal PublicSite::Urls.new.path_for(post, "en"), items[:post].url_path
    assert_equal "Albatross sighting", items[:post].title
    assert_nil items[:post].where
    assert_equal post.reload.published_at, items[:post].date
    assert_includes items[:post].snippet.text, "Albatross"
  end

  test "the hits keep the engine's order" do
    first = index(create_page(title: "Albatross"))
    second = index(create_page(title: "Petrel", translations: { "en" => { title: "Petrel", subtitle: "Albatross" } }))

    assert_equal [ first.id, second.id ], shown("albatross").map { |item| item.record.id }
  end

  test "a post result lists its copy's tags in order" do
    listing
    post = index(create_post(title: "Albatross", tags: %w[seabirds deployments ocean]))

    assert_equal %w[seabirds deployments ocean], shown_item_of(post).tags
  end

  test "a page result has none" do
    assert_equal [], shown_item_of(index(create_page(title: "Albatross"))).tags
  end

  test "a renamed tag shows its old name until the post is published" do
    listing
    post = index(create_post(title: "Albatross", tags: %w[gull]))
    assert Tags::Rename.call(Tag.named("gull").first, name: "seagull").ok?

    assert_equal %w[gull], shown_item_of(post).tags
    index(publish_changes(post))
    assert_equal %w[seagull], shown_item_of(post).tags
  end

  test "an item is close when its hit is" do
    page = index(create_page(title: "Albatross"))
    hit = results("albatross").hits.first
    close = SiteSearch::Results.new(hits: [ hit.with(close: true) ], total: 1)

    assert_equal false, shown_item_of(page).close
    assert_equal true, SiteSearch::Shown.for(close, locale: "en", now: Time.current).first.close
  end

  test "ten hits cost a constant number of statements" do
    listing
    section = create_page(title: "Seabirds")
    deeper = create_page(title: "Ocean", parent: section)
    pages = 5.times.map { |index| index(create_page(title: "Albatross #{index}", parent: [ root_page, section, deeper ][index % 3])) }
    posts = 5.times.map { |index| index(create_post(title: "Albatross post #{index}")) }
    two = SiteSearch::Results.new(hits: results("albatross").hits.select { |hit| [ pages.first.id, posts.first.id ].include?(hit.record_id) }.uniq { |hit| hit.record_type }, total: 2)
    ten = results("albatross")
    assert_equal [ 2, 10 ], [ two.hits.size, ten.hits.size ]
    SiteSearch::Shown.for(two, locale: "en", now: Time.current) # settles what a first read memoises (the settings row)

    counts = [ two, ten ].map do |answer|
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
      items = ActiveRecord::Base.uncached do
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          SiteSearch::Shown.for(answer, locale: "en", now: Time.current).each(&:tags)
        end
      end
      assert_equal answer.hits.size, items.size
      count
    end

    assert_equal counts.first, counts.last, "a page and a post cost what five of each do"
    assert_equal SHOWN_STATEMENTS, counts.last, "SiteSearch::Shown's statements, a post's tags read included"
  end

  # The agreement of the built-in's query with the re-check (spec §5.6, "with
  # the built-in the check drops nothing"): every record the query returns
  # passes `Shown`, over the cases the query itself must leave out.
  test "every record SiteSearch::Postgres::Query returns passes Shown" do
    blog = listing
    create_page(title: "Albatross draft", published: false)
    scheduled = create_page(title: "Albatross scheduled")
    Page.where(id: scheduled.id).update_all(published_at: 1.day.from_now) # version: none (a test schedules the record around the services)
    trashed = create_page(title: "Albatross trashed")
    assert Trash::Move.call(trashed).ok?
    unaddressed = create_page(title: "Albatross unaddressed")
    PublicPath.where(record_type: "Page", record_id: unaddressed.id, locale: "en").delete_all # version: none (a test takes an address away)
    hidden = create_page(title: "Hidden section", published: false)
    create_page(title: "Albatross below a draft", parent: hidden)
    visible = create_page(title: "Albatross visible")
    post = create_post(title: "Albatross post")
    assert_equal blog.id, PublicPath.find_by!(record_type: "Post", record_id: post.id, locale: "en", current: true).listed_on_id

    query = query("albatross")
    found = SiteSearch::Postgres::Query.new(query, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3).results
    items = SiteSearch::Shown.for(found, locale: "en", now: query.now)

    assert_equal [ [ "Page", visible.id ], [ "Post", post.id ] ].sort, found.hits.map { |hit| [ hit.record_type, hit.record_id ] }.sort
    assert_equal found.hits.map { |hit| [ hit.record_type, hit.record_id ] }, items.map { |item| [ item.record.class.polymorphic_name, item.record.id ] }

    # The close pass, for a typo, and the contains pass, in Japanese, by the
    # same rules.
    typo = postgres_results(query("albatros"))
    assert typo.hits.any? && typo.hits.all?(&:close), "the typo finds close hits"
    assert_equal [ [ "Page", visible.id ], [ "Post", post.id ] ].sort, typo.hits.map { |hit| [ hit.record_type, hit.record_id ] }.sort
    assert_equal typo.hits.size, SiteSearch::Shown.for(typo, locale: "en", now: query.now).size

    with_locales(Locales.enabled | %w[ja], default: Locales.default)
    live = create_page(title: "Japanese live", translations: { "ja" => { title: "検索エンジン", slug: "japanese-live" } })
    create_page(title: "Japanese draft", published: false, translations: { "ja" => { title: "検索エンジン案", slug: "japanese-draft" } })
    create_page(title: "Japanese below", parent: hidden, translations: { "ja" => { title: "検索エンジン下", slug: "japanese-below" } })
    japanese = query("エンジン").with(language: "ja")
    contained = postgres_results(japanese)
    assert_equal [ [ "Page", live.id ] ], contained.hits.map { |hit| [ hit.record_type, hit.record_id ] }
    assert_equal 1, SiteSearch::Shown.for(contained, locale: "ja", now: japanese.now).size
  end

  def postgres_results(query) = SiteSearch::Postgres::Query.new(query, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3).results
end
