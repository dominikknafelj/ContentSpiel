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

  test "a database query produces its own span, not just the request's" do
    Page.count

    db_spans = @exporter.finished_spans.select { |span| span.attributes["db.statement"]&.include?("pages") }
    assert db_spans.any?, "expected a span for the query against the pages table"
  end
end
