require "test_helper"

# `SiteSearch.search` is the one caller of a backend's `search` (spec §5.7):
# it hands the backend a deadline, and a backend that raises or answers past
# it is `SiteSearch::UNAVAILABLE`, reported at most once a minute by its
# name and its error's class. The `search.query` span (spec §9) records the
# backend, the outcome, the total and the page, and never the query.
class SiteSearchTest < ActiveSupport::TestCase
  QUERY = "zanzibar-canary-query".freeze
  SECRET = "http://engine/select?q=#{QUERY}".freeze

  def query(text = QUERY, page: 1) = SiteSearch::Query.new(text: text, language: "en", page: page, per_page: 10, now: Time.current)

  def written(spans)
    spans.map do |span|
      [ span.name, span.attributes.to_a, span.status&.description,
        Array(span.events).map { |event| [ event.name, event.attributes.to_a ] } ].flatten.compact.join(" ")
    end.join("\n")
  end

  # A span is recorded only under a request's server span
  # (`Telemetry::WorkSampler`), so the search runs inside one.
  def in_request(&block) = OpenTelemetry.tracer_provider.tracer("site-search-test").in_span("GET /search", kind: :server, &block)

  setup do
    @exporter = Rails.application.config.x.otel_test_exporter
    @exporter.reset
  end

  test "a backend that raises answers unavailable and reports once a minute without the message" do
    SiteSearch::Fake.new(raise_with: RuntimeError.new(SECRET)).installed do
      report = assert_error_reported(SiteSearch::Unavailable) do
        assert_equal SiteSearch::UNAVAILABLE, SiteSearch.search(query)
      end
      assert_includes report.error.message, "RuntimeError"
      assert_not_includes report.error.message, QUERY
      assert_nil report.error.cause

      assert_no_error_reported { assert_equal SiteSearch::UNAVAILABLE, SiteSearch.search(query) }

      travel(SiteSearch::Reports::WITHIN + 1.second) do
        assert_error_reported(SiteSearch::Unavailable) { SiteSearch.search(query) }
      end
    end
  end

  test "a backend that answers past the deadline is unavailable" do
    stub_const(SiteSearch, :TIMEOUT, 0.05) do
      SiteSearch::Fake.new(sleep_for: SiteSearch::TIMEOUT + 0.1).installed do
        assert_error_reported(SiteSearch::Unavailable) { assert_equal SiteSearch::UNAVAILABLE, SiteSearch.search(query) }
      end
    end
  end

  # A backend that does not watch its deadline and answers late is late all
  # the same: its answer is not drawn.
  test "an answer handed back after the deadline is unavailable" do
    late = Class.new(SiteSearch::Fake) do
      def search(query, deadline:)
        sleep 0.1
        super(query, deadline: deadline + 1)
      end
    end
    stub_const(SiteSearch, :TIMEOUT, 0.05) do
      late.new.installed { assert_equal SiteSearch::UNAVAILABLE, SiteSearch.search(query) }
    end
  end

  test "the backend's deadline is TIMEOUT from now, on the monotonic clock" do
    asked = nil
    fake = SiteSearch::Fake.new
    fake.define_singleton_method(:search) { |query, deadline:| (asked = deadline) && super(query, deadline: deadline) }
    before = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    fake.installed { assert_kind_of SiteSearch::Results, SiteSearch.search(query) }

    assert_in_delta before + SiteSearch::TIMEOUT, asked, 0.5
    assert_equal 3, SiteSearch::TIMEOUT
  end

  test "search.query records backend, outcome, total and page, never the query" do
    fake = SiteSearch::Fake.new
    fake.index([ document(QUERY) ])

    fake.installed { in_request { SiteSearch.search(query(page: 2)) } }

    span = @exporter.finished_spans.find { |each| each.name == "search.query" }
    assert span, @exporter.finished_spans.map(&:name).inspect
    assert_equal :internal, span.kind
    server = @exporter.finished_spans.find { |each| each.kind == :server }
    assert_equal server.span_id, span.parent_span_id, "under the request's server span"
    assert_equal({ "search.backend" => "test/fake", "search.outcome" => "results", "search.results" => 1, "search.page" => 2 }, span.attributes.to_h)
    assert_not_includes written(@exporter.finished_spans), QUERY
  end

  test "search.query of a search with no hits records none" do
    SiteSearch::Fake.new.installed { in_request { SiteSearch.search(query) } }

    span = @exporter.finished_spans.find { |each| each.name == "search.query" }
    assert_equal "none", span.attributes["search.outcome"]
    assert_equal 0, span.attributes["search.results"]
  end

  # The exception event a raise inside a span writes holds the error's
  # message, and an engine's message holds the address it asked.
  test "the span of a failed search holds neither the query nor the engine's message" do
    SiteSearch::Fake.new(raise_with: RuntimeError.new(SECRET)).installed do
      assert_error_reported(SiteSearch::Unavailable) { in_request { SiteSearch.search(query) } }
    end

    span = @exporter.finished_spans.find { |each| each.name == "search.query" }
    assert span, @exporter.finished_spans.map(&:name).inspect
    assert_equal "unavailable", span.attributes["search.outcome"]
    assert_equal %w[search.backend search.outcome search.page search.results], span.attributes.keys.sort
    text = written(@exporter.finished_spans)
    assert_not_includes text, QUERY
    assert_not_includes text, "engine/select"
  end

  # A backend's answer is checked inside the scrubbed path: what it hands
  # back is a gem's, and a total that is no Integer or a mark that is no
  # pair of Integers would raise in the page's drawing, a 500.
  test "an answer of the wrong shape is unavailable, reported by its class, never a 500" do
    snippet = SiteSearch::Snippet.new(text: "an albatross", marks: [ [ 3, 9 ] ])
    hit = ->(**changes) { SiteSearch::Hit.new(record_type: "Page", record_id: 1, copy_id: 1, language: "en", snippet: snippet, rank: 1.0).with(**changes) }
    answers = {
      "a nil total" => SiteSearch::Results.new(hits: [], total: nil),
      "a String total" => SiteSearch::Results.new(hits: [], total: "3"),
      "nil hits" => SiteSearch::Results.new(hits: nil, total: 1),
      "a Hash" => { hits: [], total: 0 },
      "a String record id" => SiteSearch::Results.new(hits: [ hit.(record_id: "1") ], total: 1),
      "a nil copy id" => SiteSearch::Results.new(hits: [ hit.(copy_id: nil) ], total: 1),
      "a hit that is no Hit" => SiteSearch::Results.new(hits: [ { record_id: 1 } ], total: 1),
      "a snippet text that is no String" => SiteSearch::Results.new(hits: [ hit.(snippet: snippet.with(text: 42)) ], total: 1),
      "a String mark" => SiteSearch::Results.new(hits: [ hit.(snippet: snippet.with(marks: [ [ "3", 9 ] ])) ], total: 1),
      "a mark of three" => SiteSearch::Results.new(hits: [ hit.(snippet: snippet.with(marks: [ [ 3, 9, 1 ] ])) ], total: 1),
      "marks that are no Array" => SiteSearch::Results.new(hits: [ hit.(snippet: snippet.with(marks: "3,9")) ], total: 1)
    }

    answers.each_with_index do |(name, answer), index|
      fake = SiteSearch::Fake.new
      fake.define_singleton_method(:search) { |_query, deadline:| answer }
      fake.installed do
        travel((SiteSearch::Reports::WITHIN + 1.second) * (index + 1)) do
          report = assert_error_reported(SiteSearch::Unavailable) { assert_equal SiteSearch::UNAVAILABLE, SiteSearch.search(query), name }
          assert_equal "test/fake: TypeError", report.error.message, name
        end
      end
    end
  end

  test "a well-formed answer is handed on, a nil snippet included" do
    fake = SiteSearch::Fake.new
    answer = SiteSearch::Results.new(hits: [ SiteSearch::Hit.new(record_type: "Page", record_id: 1, copy_id: 2, language: "en", snippet: nil, rank: 1) ], total: 1)
    fake.define_singleton_method(:search) { |_query, deadline:| answer }

    fake.installed { assert_equal answer, SiteSearch.search(query) }
  end

  test "a snippet longer than SNIPPET_LENGTH is cut at a word boundary, and the marks past the cut are dropped" do
    assert_equal 500, SiteSearch::SNIPPET_LENGTH
    words = ("albatross " * 80).strip
    marks = (0...80).map { |index| [ index * 10, 9 ] }
    fake = SiteSearch::Fake.new
    fake.define_singleton_method(:search) do |_query, deadline:|
      SiteSearch::Results.new(hits: [ SiteSearch::Hit.new(record_type: "Page", record_id: 1, copy_id: 2, language: "en",
        snippet: SiteSearch::Snippet.new(text: words, marks: marks), rank: 1) ], total: 1)
    end

    snippet = fake.installed { SiteSearch.search(query) }.hits.first.snippet

    assert_operator snippet.text.length, :<=, SiteSearch::SNIPPET_LENGTH
    assert_equal words[0, snippet.text.length], snippet.text
    assert snippet.text.end_with?("albatross"), "cut at a word boundary"
    assert_equal marks.select { |start, length| start + length <= snippet.text.length }, snippet.marks
    assert(snippet.marks.all? { |start, length| snippet.text[start, length] == "albatross" })

    short = SiteSearch::Snippet.new(text: "an albatross", marks: [ [ 3, 9 ] ])
    assert_same short, SiteSearch.cut_snippet(short)
  end

  test "a counter store that raises leaves the search answering, the failure reported" do
    broken = Object.new
    broken.define_singleton_method(:write) { |*, **| raise Errno::ECONNREFUSED, "cache at postgres://secret" }

    with_singleton_override(CounterStore, :current, -> { broken }) do
      SiteSearch::Fake.new(raise_with: RuntimeError.new(SECRET)).installed do
        assert_error_reported(SiteSearch::Unavailable) { assert_equal SiteSearch::UNAVAILABLE, SiteSearch.search(query) }
      end
      assert_nothing_raised { SiteSearch::Reports.report_block_text(block_type: "acme/gallery", error: RuntimeError.new("boom")) }
    end
  end

  test "a scrubbed failure keeps the backend's backtrace, and no message or cause" do
    raised = nil
    error = assert_raises(SiteSearch::Unavailable) do
      SiteSearch::Unavailable.scrubbing(backend: "test/fake") do
        raise RuntimeError, SECRET
      rescue RuntimeError => original
        raised = original
        raise
      end
    end

    assert_equal raised.backtrace, error.backtrace
    assert_equal "test/fake: RuntimeError", error.message
    assert_nil error.cause
  end

  private

  def document(word)
    now = 1.day.ago
    SiteSearch::Document.new(key: "Page:1:1:en", record_type: "Page", record_id: 1, copy_id: 1, language: "en", url: "/x",
      live_at: now, shown_from: now, shown_until: nil,
      fields: [ SiteSearch::Field.new(name: "title", weight: :a, text: word) ], text: word)
  end
end
