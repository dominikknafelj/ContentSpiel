require "test_helper"

# A visitor's query is personal data (search spec §8.4): the CMS logs,
# traces, stores, caches and reports none of it. A canary query is searched
# for, searched through a backend that fails with the query in its message
# (as an engine's client does: `/select?q=…`), and sent through the
# default-language redirect, which keeps the query string; then every place
# the CMS writes to is read for it.
class PublicSearchPrivacyTest < ActionDispatch::IntegrationTest
  include LogCapture

  CANARY = "QUERY-CANARY-7f3a".freeze

  # Collects every error reported, handled or not.
  class Reports
    attr_reader :all

    def initialize = @all = []
    def report(error, **context) = @all << [ error, context ]
  end

  setup do
    site_settings(:default).update!(setup_completed_at: Time.current)
    @exporter = Rails.application.config.x.otel_test_exporter
    @exporter.reset
    @reports = Reports.new
    Rails.error.subscribe(@reports)
  end

  teardown { Rails.error.unsubscribe(@reports) }

  def spans_text
    @exporter.finished_spans.map do |span|
      [ span.name, span.attributes.to_a, span.status&.description,
        Array(span.events).map { |event| [ event.name, event.attributes.to_a ] } ].flatten.compact.join(" ")
    end.join("\n")
  end

  # Every row of every table, as text.
  def tables_text
    connection = ActiveRecord::Base.connection
    connection.tables.map do |table|
      connection.select_all("SELECT * FROM #{connection.quote_table_name(table)}").rows.flatten.compact.map(&:to_s).join(" ")
    end.join("\n")
  end

  def store_text(store)
    return "" unless store.respond_to?(:instance_variable_get) && (data = store.instance_variable_get(:@data))

    data.map { |key, entry| [ key, entry.respond_to?(:value) ? entry.value : entry ].inspect }.join("\n")
  end

  test "a query reaches no log, span, table, cache or error report, at debug either" do
    log = nil
    place_search_block(root_page)
    create_page(title: "Albatross")

    log = capture_log(LogCapture::REQUEST_LOGGERS) do
      Rails.logger.level = :debug
      get "/", params: { q: CANARY }
      assert_response :success
      assert_equal "none", search_drawn[:state], "the backend was asked"

      get "/en", params: { q: CANARY }
      assert_response :found
      assert_includes response.location, CANARY, "the redirect keeps the query for the visitor"
    end

    SiteSearch::Fake.new(raise_with: RuntimeError.new("http://engine/select?q=#{CANARY}")).installed do
      log += capture_log(LogCapture::REQUEST_LOGGERS) { get "/", params: { q: CANARY } }
      assert_equal "unavailable", search_drawn[:state]
    end

    assert_match(/Started GET "\/\?q=\[FILTERED\]"/, log)
    assert_match(/Redirected to \S+\?q=\[FILTERED\]/, log)
    assert_match(/search_entries.*\["q", "\[FILTERED\]"\]/, log, "the search's statement is logged at debug, with its bind filtered")
    assert_not_includes log, CANARY
    assert_not_includes spans_text, CANARY
    assert @exporter.finished_spans.any? { |span| span.name == "search.query" }, "the search's span is recorded"
    assert_not_includes tables_text, CANARY
    assert_not_includes store_text(CounterStore.current), CANARY
    assert @reports.all.any?, "the failure was reported"
    assert_not_includes @reports.all.inspect, CANARY
    assert_not_includes @reports.all.map { |error, _| error.message }.join, CANARY
  end

  # Old links and Latin-1 forms send bytes that are no UTF-8 (`caf%E9`):
  # Rails' encoding check would refuse the request with a message that holds
  # the value, and that message is logged in production too.
  test "a query that is no UTF-8 is searched, scrubbed, and reaches no log" do
    log = nil
    place_search_block(root_page)
    log = capture_log(LogCapture::REQUEST_LOGGERS) do
      get "/?q=#{CANARY}%FF"
      assert_response :success
      assert_equal "none", search_drawn[:state]

      get "/?q=#{"a" * 201}%FF"
      assert_response :success
      assert_equal "too_long", search_drawn[:state]

      sign_in_as(users(:one))
      get "/cs-studio/preview?q=#{CANARY}%FF"
      assert_response :success
      assert_equal "none", search_drawn[:state]
    end

    assert_match(/Started GET "\/\?q=\[FILTERED\]"/, log)
    assert_not_includes log, CANARY
    assert_not_includes log, "BadRequest"
  end

  # `/en/%2Fevil.com` decodes to the path "/evil.com", and the default
  # language's redirect would point at `//evil.com`: another host, which
  # Rails refuses with an error whose message holds the location, and so
  # the query, in the span and the report.
  test "a path that begins with a slash once decoded redirects on the site's own host, never a 500 that carries the query" do
    log = capture_log(LogCapture::REQUEST_LOGGERS) do
      [ "/en/%2Fevil.com", "/en/%2F%2Fevil.com", "/en/%5Cevil.com", "/en/%2F%5Cevil.com" ].each do |path|
        get "#{path}?q=#{CANARY}"
        assert_response :found, path
        assert_equal "http://www.example.com/evil.com?q=#{CANARY}", response.location, path
      end
    end

    assert_not_includes log, CANARY
    assert_not_includes spans_text, CANARY
    assert_not_includes @reports.all.inspect, CANARY
    assert_empty @reports.all, "nothing was raised"
  end

  # Rails' redirect check parses the location and raises on one it cannot
  # read (a space, a tab, a quote, a brace, a letter outside ASCII), with
  # the location in the message: each segment is percent-encoded, so the
  # location is always a plain path on the site's own host.
  test "a path with characters no location may hold redirects encoded on the site's own host, never a 500 that carries the query" do
    cases = {
      "/en/%09/evil.com" => "/%09/evil.com",
      "/en/%2F%09%2Fevil.com" => "/%09/evil.com",
      "/en/%09%2F%2Fevil.com" => "/%09//evil.com",
      "/en/%20//evil.com" => "/%20/evil.com",
      "/en/%E2%80%8B//evil.com" => "/%E2%80%8B/evil.com",
      "/en/a%0D%0ALocation:%20http://evil.com" => "/a%0D%0ALocation%3A%20http%3A/evil.com",
      "/en/a%20b" => "/a%20b",
      "/en/caf%C3%A9" => "/caf%C3%A9",
      "/en/%22x" => "/%22x",
      "/en/%7Bx%7D" => "/%7Bx%7D"
    }
    log = capture_log(LogCapture::REQUEST_LOGGERS) do
      cases.each do |path, location|
        get "#{path}?q=#{CANARY}"
        assert_response :found, path
        assert_equal "http://www.example.com#{location}?q=#{CANARY}", response.location, path
      end
    end

    assert_not_includes log, CANARY
    assert_not_includes spans_text, CANARY
    assert_not_includes @reports.all.inspect, CANARY
    assert_empty @reports.all, "nothing was raised"
  end

  test "an accented slug under the default language's prefix redirects to its page" do
    page = create_page(title: "Über uns", translations: { "en" => { title: "Über uns", slug: "über-uns" }, "de" => { title: "Über uns", slug: "über-uns" } })

    get "/en/%C3%BCber-uns?q=#{CANARY}"
    assert_response :found
    assert_equal "http://www.example.com/%C3%BCber-uns?q=#{CANARY}", response.location

    get "/%C3%BCber-uns"
    assert_response :success
    assert_includes response.body, "Über uns"
    assert_equal "/über-uns", PublicSite::Urls.new.path_for(page, "en")

    get "/de/%C3%BCber-uns"
    assert_response :success, "a language that is not the default is not redirected, and its encoded slug finds the page"
    assert_includes response.body, "Über uns"
  end

  test "an outside backend's failure is reported without its exception's message" do
    place_search_block(root_page)

    SiteSearch::Fake.new(raise_with: RuntimeError.new("http://engine/select?q=#{CANARY}")).installed do
      report = assert_error_reported(SiteSearch::Unavailable) { get "/", params: { q: CANARY } }
      assert_response :success
      assert_equal "#{SiteSearch::Fake::NAME}: RuntimeError", report.error.message
      assert_nil report.error.cause
      assert_nil report.error.backtrace&.find { |line| line.include?(CANARY) }
    end
  end

  def post_suggestion(suggest:, language: "en")
    post "/search/suggestions", params: { suggest: suggest, language: language }.to_json,
      headers: { "Content-Type" => "application/json", "Sec-Fetch-Site" => "same-origin" }
  end

  # The block run with the request loggers at debug, then every place the
  # CMS writes to as one text: the log, the spans, the tables, the counters'
  # store and the errors reported with their messages.
  def capture_everything
    log = capture_log(LogCapture::REQUEST_LOGGERS) do
      Rails.logger.level = :debug
      yield
    end
    [ log, spans_text, tables_text, store_text(CounterStore.current), @reports.all.inspect,
      @reports.all.map { |error, _| error.message }.join ].join("\n")
  end

  test "a suggestion's prefix reaches no log, span, table, cache or error report" do
    place_search_block(root_page)
    create_page(title: "Albatross")
    planted = "zqxprefix#{SecureRandom.hex(3)}"
    everything = capture_everything do
      post_suggestion(suggest: planted)
      assert_response :ok
      post_suggestion(suggest: "alba #{planted}")
      post "/search/suggestions", params: "{\"suggest\": \"#{planted}", headers: { "Content-Type" => "application/json" }
      assert_response :bad_request
      SiteSearch::Fake.new(raise_with: RuntimeError.new("http://engine/suggest?q=#{planted}")).installed do
        post_suggestion(suggest: planted)
        assert_equal "unavailable", response.parsed_body["state"]
      end
    end

    assert_match(/"suggest" => "\[FILTERED\]"/, everything, "the Parameters line names the key, filtered")
    assert @exporter.finished_spans.any? { |span| span.name == "search.suggest" }, "the suggestion's span is recorded"
    refute_includes everything, planted
  end

  test "an outside backend's suggest failure is reported without its message" do
    SiteSearch::Fake.new(raise_with: RuntimeError.new("secret alba")).installed do
      report = assert_error_reported(SiteSearch::Unavailable) { post_suggestion(suggest: "alba") }
      assert_response :ok
      assert_equal "#{SiteSearch::Fake::NAME}: RuntimeError", report.error.message
      assert_nil report.error.cause
    end
    assert_equal [ "SiteSearch::Unavailable" ], @reports.all.map { |error, _| error.class.name }
    refute @reports.all.any? { |error, _| error.message.include?("secret") }
  end

  test "suggest is filtered and suggested_at is not" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    assert_equal({ "suggest" => "[FILTERED]", "suggested_at" => "x" }, filter.filter("suggest" => "a", "suggested_at" => "x"))
  end
end
