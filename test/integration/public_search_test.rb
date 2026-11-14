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
      page = create_page(title: "Albatross")
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
end
