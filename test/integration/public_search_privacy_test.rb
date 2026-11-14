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
    with_search_probe do
      place_search_probe(root_page)
      create_page(title: "Albatross")

      log = capture_log(LogCapture::REQUEST_LOGGERS) do
        Rails.logger.level = :debug
        get "/", params: { q: CANARY }
        assert_response :success
        assert_equal "none", probe[:state], "the backend was asked"

        get "/en", params: { q: CANARY }
        assert_response :found
        assert_includes response.location, CANARY, "the redirect keeps the query for the visitor"
      end
    end

    SiteSearch::Fake.new(raise_with: RuntimeError.new("http://engine/select?q=#{CANARY}")).installed do
      with_search_probe do
        log += capture_log(LogCapture::REQUEST_LOGGERS) { get "/", params: { q: CANARY } }
        assert_equal "unavailable", probe[:state]
      end
    end

    assert_match(/Started GET "\/\?q=\[FILTERED\]"/, log)
    assert_match(/Redirected to \S+\?q=\[FILTERED\]/, log)
    assert_match(/search_entries.*\["q", "\[FILTERED\]"\]/, log, "the search's statement is logged at debug, with its bind filtered")
    assert_not_includes log, CANARY
    assert_not_includes spans_text, CANARY
    assert @exporter.finished_spans.any? { |span| span.name == "search.query" }, "the search's span is recorded"
    assert_not_includes tables_text, CANARY
    assert_not_includes store_text(CounterStore.current), CANARY
    assert_not_includes store_text(Rails.cache), CANARY
    assert @reports.all.any?, "the failure was reported"
    assert_not_includes @reports.all.inspect, CANARY
    assert_not_includes @reports.all.map { |error, _| error.message }.join, CANARY
  end

  test "an outside backend's failure is reported without its exception's message" do
    with_search_probe { place_search_probe(root_page) }

    SiteSearch::Fake.new(raise_with: RuntimeError.new("http://engine/select?q=#{CANARY}")).installed do
      with_search_probe do
        report = assert_error_reported(SiteSearch::Unavailable) { get "/", params: { q: CANARY } }
        assert_response :success
        assert_equal "#{SiteSearch::Fake::NAME}: RuntimeError", report.error.message
        assert_nil report.error.cause
        assert_nil report.error.backtrace&.find { |line| line.include?(CANARY) }
      end
    end
  end
end
