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
end
