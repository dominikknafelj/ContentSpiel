require "test_helper"

# config/initializers/opentelemetry.rb configures the SDK once at boot, with
# `opentelemetry-instrumentation-all` auto-instrumenting Rack/ActionPack/
# ActiveRecord/etc with zero code changes to the app itself. That makes it
# easy to get wrong in a way nothing else would catch -- a typo'd exporter, a
# processor that never flushes, an instrumentation gem that silently didn't
# install -- so this proves a real request actually produces a span, not
# just that the gems are in the Gemfile.
class OpenTelemetryTest < ActionDispatch::IntegrationTest
  setup do
    @exporter = Rails.application.config.x.otel_test_exporter
    @exporter.reset
  end

  test "test environment uses the in-memory exporter, not console or otlp" do
    assert_instance_of OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter, @exporter
  end

  # SimpleSpanProcessor (config/initializers/opentelemetry.rb) exports
  # synchronously as each span ends, so this can assert immediately after the
  # request -- no flush or async wait needed, unlike the BatchSpanProcessor
  # used for a real OTLP backend.
  test "a request produces at least one span" do
    get "/up"

    assert_response :success
    assert @exporter.finished_spans.any?, "expected at least one span to be recorded for the request"
  end

  # A query is recorded only inside a trace that is kept: the ActiveRecord
  # instrumentation makes a span for a bare model call too, but with no
  # request or job around it that span is a root of its own and
  # `Telemetry::WorkSampler` drops it (the tests after this one show both
  # sides), so this has to run inside a real request.
  #
  # PG instrumentation (opentelemetry-instrumentation-pg) is deliberately
  # disabled (config/initializers/opentelemetry.rb) -- it segfaulted
  # `bin/rails test`'s forked parallel workers. ActiveRecord instrumentation
  # is a separate gem/code path and unaffected; this is what proves that.
  test "a database query within a request produces its own span" do
    Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    @exporter.reset

    get "/"

    assert_response :success
    query_spans = @exporter.finished_spans.select { |span| span.name.start_with?("Page ", "Page.") }
    assert query_spans.any?, "expected a span for the query against Page, got: #{@exporter.finished_spans.map(&:name)}"
  end

  # What is sent is the work a request or a job caused, and nothing of the
  # background's polling (lib/telemetry/work_sampler.rb). In production Solid
  # Cable's listener and Solid Queue's worker query their tables several
  # times a second from threads of their own, each query the root of a
  # trace; that was about 820,000 spans a day on an idle site. The test
  # environment has neither (its cable adapter is `test` and its jobs are
  # not polled for), so a poll is stood for by what it is to the sampler: a
  # query with no request and no job around it, on the test's thread and on
  # a thread of its own.
  test "a request is recorded with its database spans, in one trace under the request's server span" do
    Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
    @exporter.reset

    get "/"

    assert_response :success
    spans = @exporter.finished_spans
    roots = spans.select { |span| root?(span) }
    assert_equal [ :server ], roots.map(&:kind), "one root, the request's: #{spans.map(&:name)}"
    assert_equal [ roots.first.trace_id ], spans.map(&:trace_id).uniq, "every span of the request is in its trace"
    assert spans.any? { |span| span.name == "Page query" }, "the request's query against Page is recorded: #{spans.map(&:name)}"
  end

  class ProbeJob < ApplicationJob
    def perform
      Page.order(:id).to_a
      Page.transaction { Page.where(id: 0).to_a }
    end
  end

  test "a job's perform is recorded with its database spans, in one trace under the job's consumer span" do
    ProbeJob.perform_now

    spans = @exporter.finished_spans
    roots = spans.select { |span| root?(span) }
    assert_equal [ [ "default process", :consumer ] ], roots.map { |span| [ span.name, span.kind ] }, spans.map(&:name).inspect
    assert_equal [ roots.first.trace_id ], spans.map(&:trace_id).uniq, "every span of the job is in its trace"
    assert_operator spans.count { |span| span.name == "Page query" }, :>=, 2, spans.map(&:name).inspect
    assert_includes spans.map(&:name), "ActiveRecord.transaction"
  end

  test "a query outside any request or job, as a poll's is, records nothing" do
    poll = -> do
      Page.order(:id).to_a
      Page.transaction { Page.where(id: 0).to_a }
    end

    poll.call
    Thread.new { ActiveRecord::Base.connection_pool.with_connection { poll.call } }.join

    assert_empty @exporter.finished_spans.map(&:name)
  end

  # The two routes that carried a password-reset token in their path. The
  # word standing for the token is no valid token, which is beside the point:
  # the path is recorded before anybody asks whether it is one. Every
  # attribute, name and event of every span of the request is read, so an
  # instrumentation that starts to write the path somewhere new fails here.
  test "no span of a request to a reset address carries the token" do
    word = "not-a-real-token-0123456789"

    get "/#{ContentSpiel::ADMIN_PATH}/password/#{word}/edit?from=mail"
    patch "/#{ContentSpiel::ADMIN_PATH}/password/#{word}", params: { password: "x", password_confirmation: "x" }

    spans = @exporter.finished_spans
    paths = spans.filter_map { |span| span.attributes&.[]("url.path") }
    assert_includes paths, "/#{ContentSpiel::ADMIN_PATH}/password/[FILTERED]/edit"
    assert_includes paths, "/#{ContentSpiel::ADMIN_PATH}/password/[FILTERED]"

    spans.each do |span|
      written = [ span.name, span.attributes.to_a, Array(span.events).map { |event| [ event.name, event.attributes.to_a ] } ].flatten.join(" ")
      assert_not_includes written, word, "span #{span.name.inspect} carries the token"
    end
  end

  # A note's quote travels in a query string (`note_quote`), and a note's
  # text reaches no log line. The first address is answered by a redirect
  # in the routes, before any controller: nothing has filtered its
  # parameters, and the span would hold the query as it was sent. The second
  # reaches a controller under a name nothing filters. Neither query leaves.
  test "no span carries a query string, of a request answered before a controller or by one" do
    quote = "some-private-words-of-a-note"

    get "/#{ContentSpiel::ADMIN_PATH}/settings/languages?note_quote=#{quote}"
    assert_response :moved_permanently
    get "/up?remark=#{quote}"
    assert_response :success

    spans = @exporter.finished_spans
    assert_equal [ "[FILTERED]", "[FILTERED]" ], spans.filter_map { |span| span.attributes&.[]("url.query") }

    spans.each do |span|
      written = [ span.name, span.attributes.to_a, Array(span.events).map { |event| [ event.name, event.attributes.to_a ] } ].flatten.join(" ")
      assert_not_includes written, quote, "span #{span.name.inspect} carries the query"
    end
  end

  private
    def root?(span) = span.parent_span_id == OpenTelemetry::Trace::INVALID_SPAN_ID
end
