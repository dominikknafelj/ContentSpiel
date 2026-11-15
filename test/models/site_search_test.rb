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
    assert_equal({ "search.backend" => "test/fake", "search.outcome" => "results", "search.results" => 1, "search.page" => 2,
      "search.close" => "none", "search.correction" => false }, span.attributes.to_h)
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
    assert_equal %w[search.backend search.close search.correction search.outcome search.page search.results], span.attributes.keys.sort
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
      "a total past 2**53" => SiteSearch::Results.new(hits: [], total: 10**309),
      "a negative total" => SiteSearch::Results.new(hits: [], total: -1),
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

  # The correction (spec §3.5) is the backend's, and ContentSpiel verifies
  # it whatever the backend: an outside engine's spellcheck reads its whole
  # index, scheduled copies included, so it is drawn only when a search for
  # it finds a page a visitor sees now.
  test "a correction is drawn only when a search for it finds a live page" do
    SiteSearch::Fake.new.installed do |fake|
      fake.answer_with(SiteSearch::Results.new(hits: [], total: 0, correction: "albatross"))
      fake.answer_for("albatross", exact_hit_of(published_page))
      assert_equal "albatross", answer_for("albatros").correction
      fake.answer_for("albatross", SiteSearch::Results.new(hits: [], total: 0))
      assert_nil answer_for("albatros").correction
    end
  end

  test "a correction blank, too long, equal to the query ignoring case, or made of syntax is dropped" do
    [ " ", "a" * 201, "ALBATROS", "*:*" ].each do |bad|
      with_fake_correction(bad) { assert_nil answer_for("albatros").correction, bad.inspect }
    end
  end

  test "a correction is normalised before it is verified and drawn" do
    with_fake_correction("  albatross\n ") { assert_equal "albatross", answer_for("albatros").correction }
  end

  # The anti-goal (spec §1): a word that only a scheduled copy holds, or
  # only a live page's scheduled change, is never offered before its time,
  # whatever an engine answers for it.
  test "a word only a scheduled copy holds is never a correction" do
    scheduled = create_page(title: "Placeholder", published: false)
    assert Pages::Save.call(scheduled.reload, translations: { "en" => { title: "Zephyrine" } }, attributes: { published_at: 1.day.from_now }).ok?
    live = create_page(title: "Harbour")
    assert Pages::Save.call(live.reload, translations: { "en" => { title: "Quillwort" } }).ok?
    publish_changes(live, at: 1.day.from_now)

    # The scheduled page's copy is taken at once and waits for its
    # `published_at`; the live page's change is a copy that waits for its
    # `live_at`.
    { "zephyrine" => Publishing.baseline(scheduled), "quillwort" => Publishing.pending(live) }.each do |word, copy|
      page = copy.record
      assert_equal word.capitalize, Locales.read(Publishing::Snapshot.rebuild(copy, page), :title, locale: "en"), "the copy holds the word"
      SiteSearch::Fake.new.installed do |fake|
        fake.answer_with(SiteSearch::Results.new(hits: [], total: 0, correction: word))
        fake.answer_for(word, SiteSearch::Results.new(hits: [ hit_of(page, copy) ], total: 1))
        assert_nil answer_for(word.chop).correction, word
      end
    end
  end

  test "an answer with an exact hit offers no correction and asks no verifying search" do
    asked = []
    SiteSearch::Fake.new.installed do |fake|
      fake.answer_with(exact_hit_of(published_page).with(correction: "albatross"))
      assert_nil answer_for("albatros").correction
      asked.concat(fake.asked)
    end
    assert_equal 1, asked.size
  end

  test "the verifying search is exact, page 1, per_page 1, and not counted" do
    asked = []
    with_fake_recording(asked) { answer_for("albatros") }
    assert_equal [ true, false ], asked.map(&:close_matches)
    assert_equal [ 1, 1 ], [ asked.last.page, asked.last.per_page ]
  end

  test "the verifying search is in the query's language and view, and the total stays the search's" do
    asked = []
    found = nil
    with_fake_recording(asked) { found = SiteSearch.search(query.with(page: 3)) }
    assert_equal [ "en", "en" ], asked.map(&:language)
    assert_equal 1, asked.map(&:now).uniq.size
    assert_equal 0, found.total
  end

  # One deadline holds the search and its verification: with none left,
  # the correction is dropped unasked. The clock reads the deadline itself
  # once the search has answered.
  test "no time left skips the verifying search" do
    readings = 0
    clock = -> { (readings += 1) == 1 ? 100.0 : 100.0 + SiteSearch::TIMEOUT }
    SiteSearch::Fake.new.installed do |fake|
      fake.answer_with(SiteSearch::Results.new(hits: [], total: 0, correction: "albatross"))
      with_singleton_override(SiteSearch, :clock, clock) do
        assert_nil SiteSearch.search(query).correction
      end
      assert_equal [ true ], fake.asked.map(&:close_matches)
    end
  ensure
    SiteSearch.private_class_method :clock
  end

  test "a verifying search that fails drops the correction and keeps the answer" do
    failing = Class.new(SiteSearch::Fake) do
      def search(query, deadline:)
        raise RuntimeError, SECRET unless query.close_matches

        super
      end
    end
    failing.new.installed do |fake|
      fake.answer_with(SiteSearch::Results.new(hits: [], total: 0, correction: "albatross"))
      found = nil
      assert_error_reported(SiteSearch::Unavailable) { found = SiteSearch.search(query) }
      assert_kind_of SiteSearch::Results, found
      assert_nil found.correction
    end
  end

  test "a close that is not a Boolean, or a correction that is not a String, is unavailable" do
    [ hit_with(close: "yes"), SiteSearch::Results.new(hits: [], total: 0, correction: 42) ].each do |bad|
      assert_equal SiteSearch::UNAVAILABLE, search_with_answer(bad)
    end
  end

  test "close_matches? is true when every hit is close" do
    close = hit_with(close: true)
    exact = hit_with(close: false)
    SiteSearch::Fake.new.installed do |fake|
      fake.answer_with(close)
      assert answer_for("albatros").close_matches?
      fake.answer_with(SiteSearch::Results.new(hits: close.hits + exact.hits, total: 2))
      assert_not answer_for("albatros").close_matches?
      fake.answer_with(SiteSearch::Results.new(hits: [], total: 0))
      assert_not answer_for("albatros").close_matches?
    end
    assert_not answer_for(nil).close_matches?
    assert_nil answer_for(nil).correction
  end

  test "search.query records search.close and search.correction, never the query" do
    span = recorded_span("search.query") { answer_for("albatros") }
    assert_includes SiteSearch::CLOSE_OUTCOMES, span.attributes["search.close"]
    assert_includes [ true, false ], span.attributes["search.correction"]
    refute_includes span.attributes.values.map(&:to_s), "albatros"
  end

  test "search.close is skipped without close_matches, found with a close hit, and a backend's own otherwise" do
    assert_equal %w[none found skipped timeout], SiteSearch::CLOSE_OUTCOMES
    closes = {}
    SiteSearch::Fake.new.installed do |fake|
      closes[:skipped] = recorded_span("search.query") { SiteSearch.search(query.with(close_matches: false)) }
      fake.answer_with(hit_with(close: true))
      closes[:found] = recorded_span("search.query") { SiteSearch.search(query) }
    end
    timing_out = Class.new(SiteSearch::Fake) do
      def search(query, deadline:)
        OpenTelemetry::Trace.current_span.set_attribute("search.close", "timeout")
        super
      end
    end
    timing_out.new.installed { closes[:timeout] = recorded_span("search.query") { SiteSearch.search(query) } }

    assert_equal({ skipped: "skipped", found: "found", timeout: "timeout" }, closes.transform_values { |span| span.attributes["search.close"] })
  end

  test "search.correction is true when a correction is drawn" do
    span = recorded_span("search.query") do
      SiteSearch::Fake.new.installed do |fake|
        fake.answer_with(SiteSearch::Results.new(hits: [], total: 0, correction: "albatross"))
        fake.answer_for("albatross", exact_hit_of(published_page))
        SiteSearch.search(query("albatros"))
      end
    end
    assert_equal true, span.attributes["search.correction"]
    assert_not_includes written(@exporter.finished_spans), "albatross"
  end

  private

  def answer_for(text) = SiteSearch::Answer.for(raw_query: text, raw_page: nil, locale: :en, limited: false, live_note: false)

  def published_page = @published_page ||= create_page(title: "Albatross")

  def hit_of(page, copy) = SiteSearch::Hit.new(record_type: "Page", record_id: page.id, copy_id: copy.id, language: "en", snippet: nil, rank: 1.0)

  # Results of one exact hit of `page`'s copy in force.
  def exact_hit_of(page) = SiteSearch::Results.new(hits: [ hit_of(page, Publishing.current(page)) ], total: 1)

  # Results of one hit, of a record that exists nowhere, with `changes`.
  def hit_with(**changes)
    hit = SiteSearch::Hit.new(record_type: "Page", record_id: 1, copy_id: 1, language: "en", snippet: nil, rank: 1.0)
    SiteSearch::Results.new(hits: [ hit.with(**changes) ], total: 1)
  end

  # A fake that answers no hits and `correction`, and an exact hit of a live
  # page to a search for `correction` as it is normalised, so only the
  # rules before the verifying search can drop it.
  def with_fake_correction(correction)
    SiteSearch::Fake.new.installed do |fake|
      fake.answer_with(SiteSearch::Results.new(hits: [], total: 0, correction: correction))
      text = SiteSearch::Query.normalise(correction)
      fake.answer_for(text, exact_hit_of(published_page)) if text
      yield fake
    end
  end

  # The block's searches, with a correction offered, each query it asks
  # appended to `asked`.
  def with_fake_recording(asked)
    SiteSearch::Fake.new.installed do |fake|
      fake.answer_with(SiteSearch::Results.new(hits: [], total: 0, correction: "albatross"))
      yield fake
    ensure
      asked.concat(fake.asked)
    end
  end

  def search_with_answer(results)
    SiteSearch::Fake.new.installed do |fake|
      fake.answer_with(results)
      SiteSearch.search(query)
    end
  end

  # The finished span `name` of the block's work, run inside a request.
  def recorded_span(name, &block)
    @exporter.reset
    in_request(&block)
    @exporter.finished_spans.find { |each| each.name == name }.tap { |span| assert span, @exporter.finished_spans.map(&:name).inspect }
  end

  def document(word)
    now = 1.day.ago
    SiteSearch::Document.new(key: "Page:1:1:en", record_type: "Page", record_id: 1, copy_id: 1, language: "en", url: "/x",
      live_at: now, shown_from: now, shown_until: nil,
      fields: [ SiteSearch::Field.new(name: "title", weight: :a, text: word) ], text: word)
  end
end
