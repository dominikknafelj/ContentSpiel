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

  # ActiveRecord instrumentation only emits a span when there's already an
  # active trace to nest it under -- a bare model call from a script (no
  # request, no parent span) produces none at all, so this has to run inside
  # a real request rather than just calling `Page.count` directly.
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
end
