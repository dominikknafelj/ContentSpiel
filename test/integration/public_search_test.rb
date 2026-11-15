require "test_helper"

# A visitor's search through the request (spec §8, §5.6): what is found is
# what the public sees at the clock, from the published copies and never the
# rows; a search is counted and limited before any backend is asked, a page
# view is never counted; and a backend that fails leaves the page drawn.
# Read through the Search block on the homepage (`search_drawn`,
# test/support/search_block.rb).
class PublicSearchTest < ActionDispatch::IntegrationTest
  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
  end

  def search(text, **options) = get("/", params: { q: text }, **options)

  def titles = search_drawn[:results].map(&:first)

  def with_search_block_on_home
    place_search_block(root_page)
    yield
  end

  test "a draft, a scheduled record, a trashed record and a record under a draft page are not found, and are found once each is live" do
    with_search_block_on_home do
      draft = create_page(title: "Albatross draft", published: false)
      scheduled = Pages::Save.call(attributes: { parent: root_page, published_at: 1.day.from_now },
        translations: { "en" => { title: "Albatross scheduled" } }).record
      trashed = create_page(title: "Albatross trashed")
      assert Trash::Move.call(trashed.reload).ok?
      section = create_page(title: "Draft section", published: false)
      create_page(title: "Albatross below", parent: section)

      search "albatross"
      assert_response :success
      assert_equal "none", search_drawn[:state]
      assert_empty titles

      assert Pages::Save.call(draft.reload, attributes: { published: true }).ok?
      assert Trash::Restore.call(trashed.reload).ok?
      assert Pages::Save.call(section.reload, attributes: { published: true }).ok?
      search "albatross"
      assert_equal [ "Albatross below", "Albatross draft", "Albatross trashed" ], titles.sort

      travel_to scheduled.published_at + 1.minute do
        search "albatross"
        assert_equal [ "Albatross below", "Albatross draft", "Albatross scheduled", "Albatross trashed" ], titles.sort
      end
    end
  end

  test "a change published with a time is found by its old words until the time and by its new words after it, with no job" do
    with_search_block_on_home do
      page = create_page(title: "Albatross", translations: { "en" => { title: "Albatross", slug: "seabird" } })
      assert Pages::Save.call(page.reload, translations: { "en" => { title: "Pelican" } }).ok?
      at = 1.hour.from_now
      publish_changes(page, at: at)

      assert_no_enqueued_jobs do
        search "albatross"
        assert_equal [ "Albatross" ], titles
        search "pelican"
        assert_equal "none", search_drawn[:state]

        travel_to at + 1.minute do
          search "albatross"
          assert_equal "none", search_drawn[:state]
          search "pelican"
          assert_equal [ "Pelican" ], titles
        end
      end
    end
  end

  # The excerpted post is written first, so a tie of ranks would list it
  # first by its lower id.
  test "a post matched by a tag outranks one matched by its excerpt" do
    with_search_block_on_home do
      blog = create_page(title: "Blog")
      assert ContentBlocks::Save.call(ContentBlock.new(owner: blog), attributes: { block_type: "post_list", settings: { "content_type" => "blog" } }).ok?
      publish_changes(blog)
      excerpted = create_post(title: "Two")
      assert Posts::Save.call(excerpted.reload, translations: { "en" => { excerpt: "albatross" } }).ok?
      publish_changes(excerpted)
      create_post(title: "One", tags: [ "albatross" ])

      search "albatross"
      assert_equal [ "One", "Two" ], titles
    end
  end

  test "words typed into a live record's rows and not published are not found" do
    with_search_block_on_home do
      page = create_page(title: "Albatross")
      assert Pages::Save.call(page.reload, translations: { "en" => { title: "Pelican" } }).ok?

      search "pelican"
      assert_equal "none", search_drawn[:state]
      search "albatross"
      assert_equal [ "Albatross" ], titles, "the title as published"
    end
  end

  test "the 21st search of a minute is refused with the page drawn; a page view without q is never counted" do
    with_search_block_on_home do
      create_page(title: "Albatross")
      30.times do
        get "/"
        assert_response :success
      end

      SiteSearch::QueryLimit::VISITOR_LIMIT.times do |n|
        search "albatross"
        assert_response :success, "search #{n + 1}"
        assert_equal "results", search_drawn[:state]
      end

      with_singleton_override(SiteSearch, :search, ->(*) { flunk "a refused search asked the backend" }) do
        search "albatross"
      end
      assert_response :too_many_requests
      assert_equal "limited", search_drawn[:state], "the page is drawn, its block limited"
      assert_equal "private, no-store", response.headers["Cache-Control"]

      get "/"
      assert_response :success
      assert_equal "empty", search_drawn[:state]

      search "albatross", env: { "REMOTE_ADDR" => "203.0.113.9" }
      assert_response :success, "another visitor has counts of their own"
      assert_equal "results", search_drawn[:state]

      travel SiteSearch::QueryLimit::WITHIN + 1.second do
        search "albatross"
        assert_response :success, "a minute later the visitor searches again"
      end
    end
  end

  # 600 requests would be a slow test: the site's count is raised to the
  # limit in the store, under the key one search was seen to write.
  test "the site limit refuses the 601st search of a minute from any visitor" do
    with_search_block_on_home do
      store = SiteSearch::QueryLimit.store
      key = "rate-limit:site_search:search_site:site"
      search "albatross", env: { "REMOTE_ADDR" => "203.0.113.1" }
      assert_response :success
      assert_equal 1, store.read(key, raw: true).to_i, "the site's count is kept under #{key}"

      store.increment(key, SiteSearch::QueryLimit::SITE_LIMIT - 1)
      search "albatross", env: { "REMOTE_ADDR" => "203.0.113.2" }
      assert_response :too_many_requests
      assert_equal "limited", search_drawn[:state]

      search "albatross", env: { "REMOTE_ADDR" => "198.51.100.7" }
      assert_response :too_many_requests, "any visitor"

      get "/", env: { "REMOTE_ADDR" => "198.51.100.8" }
      assert_response :success, "a page view is still answered"
    end
  end

  test "a q that is an array or a hash is no search" do
    with_search_block_on_home do
      [ "/?q[]=a", "/?q[x]=1" ].each do |address|
        assert_no_difference -> { SiteSearch::QueryLimit.store.instance_variable_get(:@data).size } do
          get address
        end
        assert_response :success, address
        assert_equal "max-age=0, public, must-revalidate", response.headers["Cache-Control"], address
        assert_equal "empty", search_drawn[:state], address
      end
    end
  end

  test "a backend that raises, and one that sleeps past the deadline, leave the page drawn with search unavailable" do
    with_search_block_on_home { create_page(title: "Albatross") }

    SiteSearch::Fake.new(raise_with: RuntimeError.new("down")).installed do
      assert_error_reported(SiteSearch::Unavailable) { search "albatross" }
      assert_response :success
      assert_equal "unavailable", search_drawn[:state]
    end

    CounterStore.current.delete(SiteSearch::Reports::KEY) # a failure is reported once a minute
    stub_const(SiteSearch, :TIMEOUT, 0.05) do
      SiteSearch::Fake.new(sleep_for: 0.2).installed do
        assert_error_reported(SiteSearch::Unavailable) { search "albatross" }
        assert_response :success
        assert_equal "unavailable", search_drawn[:state]
      end
    end
  end
  # The built-in's close pass and contains pass (search 2 spec §3.3, §3.4),
  # read from the answer the Search block draws.
  def answer_for(text, locale: "en")
    SiteSearch::Answer.for(raw_query: text, raw_page: nil, locale: locale.to_sym, limited: false, live_note: false)
  end

  def typos = YAML.load_file(file_fixture("search_typos.yml"))

  def found_ids(answer) = answer.results.map { _1.record.id }

  # A live page titled `title` in `locale`, in the default language too.
  def create_page_in(locale, title:)
    return create_page(title: title) if locale == Locales.default

    @pages = (@pages || 0) + 1
    create_page(title: "Host #{@pages}", translations: { locale => { title: title, slug: "host-#{@pages}" } })
  end

  # Measured on Postgres 17 (test/fixtures/files/search_typos.yml): each typo
  # stems to a word no entry holds, so the exact pass finds nothing, and is
  # 0.3 or more similar to its correction.
  test "a close match finds a typo's page and ranks after every exact hit" do
    typos.each do |typo|
      page = create_page_in(typo.fetch("language", "en"), title: typo["page"])
      answer = answer_for(typo["typo"], locale: typo.fetch("language", "en"))
      assert answer.close_matches?, typo["typo"]
      assert_includes found_ids(answer), page.id
      assert_equal typo["correction"], answer.correction
    end
  end

  test "invoice finds its page exact, with no close pass" do
    page = create_page(title: "Invoice")
    create_page(title: "Voice")
    answer = answer_for("invoice")
    refute answer.close_matches?
    assert_equal [ page.id ], found_ids(answer)
  end

  test "a correction is offered only when a search for it finds a live page" do
    draft = create_page(title: "Albatross", published: false)
    assert_nil answer_for("albatros").correction
    assert Pages::Save.call(draft.reload, attributes: { published: true }).ok?
    assert_equal "albatross", answer_for("albatros").correction
  end

  test "a word only a scheduled copy holds is never a correction or a close match before its time" do
    page = create_page(title: "Plain")
    assert Pages::Save.call(page.reload, translations: { "en" => { title: "Cormorant" } }).ok?
    publish_changes(page, at: 1.day.from_now)
    answer = answer_for("cormorat")
    assert_empty answer.results
    assert_nil answer.correction
    travel(2.days) { assert_equal "cormorant", answer_for("cormorat").correction }
  end

  test "contains finds a Japanese page by a word inside its text" do
    with_locales(Locales.enabled | %w[ja], default: Locales.default)
    page = create_page_in("ja", title: "検索エンジンの使い方")
    assert_equal [ page.id ], found_ids(answer_for("エンジン", locale: "ja"))
  end

  test "a close pass that passes its share leaves the exact answer standing" do
    create_page(title: "Zero-downtime deployment")
    timing_out = Object.new.tap { |pass| def pass.plain? = true; def pass.results = raise(ActiveRecord::QueryCanceled, "statement timeout") }
    with_singleton_override(SiteSearch::Postgres::Close, :new, ->(*, **) { timing_out }) do
      answer = answer_for("deploymnet")
      assert_equal [ :none, nil ], [ answer.state, answer.correction ]
      query = SiteSearch::Query.new(text: "deploymnet", language: "en", page: 1, per_page: 10, now: Time.current)
      found = SiteSearch::Postgres::Query.new(query, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3).results
      assert_equal [ [], 0, "timeout" ], [ found.hits, found.total, found.close_outcome ]
    end
  end

  test "a close pass with no time left is a timeout, the exact answer standing" do
    create_page(title: "Zero-downtime deployment")
    stub_const(SiteSearch::Postgres, :CLOSE_SHARE, 0) do
      query = SiteSearch::Query.new(text: "deploymnet", language: "en", page: 1, per_page: 10, now: Time.current)
      found = SiteSearch::Postgres::Query.new(query, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3).results
      assert_equal [ [], 0, nil, "timeout" ], [ found.hits, found.total, found.correction, found.close_outcome ]
    end
  end

  test "a query that is not plain, and a limited language, skip the close pass" do
    create_page(title: "Zero-downtime deployment")
    with_locales(Locales.enabled | %w[ja], default: Locales.default)
    { "deploymnet -guide" => "en", "deploymnet" => "ja" }.each do |text, language|
      query = SiteSearch::Query.new(text: text, language: language, page: 1, per_page: 10, now: Time.current)
      found = SiteSearch::Postgres::Query.new(query, deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3).results
      assert_equal [ 0, nil, "skipped" ], [ found.total, found.correction, found.close_outcome ], text
    end
  end
end
