require "test_helper"

# The CMS's own spans (lib/telemetry.rb): one tracer, and a span or an
# attribute only by a name in `Telemetry::SPANS` or `Telemetry::ATTRIBUTES`.
# The spans are read on the exporter the application configured, so what a
# test reads is what a backend would be sent.
class TelemetryTest < ActiveSupport::TestCase
  setup do
    @exporter = Rails.application.config.x.otel_test_exporter
    @exporter.reset
  end

  test "in_span refuses a name that is not in SPANS and a key that is not in ATTRIBUTES, and record refuses an unlisted key" do
    ran = false

    error = assert_raises(ArgumentError) { Telemetry.in_span("auth.unlisted") { ran = true } }
    assert_includes error.message, "auth.unlisted"

    error = assert_raises(ArgumentError) { Telemetry.in_span("auth.sign_in", attributes: { "auth.typed" => "x" }) { ran = true } }
    assert_includes error.message, "auth.typed"

    error = assert_raises(ArgumentError) { Telemetry.in_span("auth.sign_in", attributes: { "auth.method": "password" }) { ran = true } }
    assert_includes error.message, "auth.method", "a Symbol key is not the listed String"

    error = assert_raises(ArgumentError) { Telemetry.in_span("auth.bot_check", kind: :clinet) { ran = true } }
    assert_includes error.message, ":clinet"

    assert_not ran, "a refused span runs no block"

    span = OpenTelemetry::Trace::Span::INVALID
    error = assert_raises(ArgumentError) { Telemetry.record(span, "auth.outcome" => "ok", "auth.email" => "x") }
    assert_includes error.message, "auth.email"
    assert_same span, Telemetry.record(span, "auth.outcome" => "ok")
  end

  test "in_span under a request's span is its child, with the kind and attributes given" do
    probe = nil
    Telemetry.tracer.in_span("probe", kind: :server) do |span|
      probe = span
      Telemetry.in_span("auth.sign_in", attributes: { "auth.method" => "password" }) do |child|
        Telemetry.record(child, "auth.outcome" => "ok")
      end
    end

    sign_in = @exporter.finished_spans.find { |span| span.name == "auth.sign_in" }
    assert sign_in, "the span is recorded: #{@exporter.finished_spans.map(&:name)}"
    assert_equal probe.context.span_id, sign_in.parent_span_id
    assert_equal :internal, sign_in.kind
    assert_equal "password", sign_in.attributes["auth.method"]
    assert_equal "ok", sign_in.attributes["auth.outcome"]

    Telemetry.tracer.in_span("probe", kind: :server) do
      Telemetry.in_span("auth.bot_check", kind: :client) { }
    end
    assert_equal :client, @exporter.finished_spans.find { |span| span.name == "auth.bot_check" }.kind
  end

  test "with no SDK the span is a no-op and the block's value comes back" do
    tracer = OpenTelemetry::Trace::TracerProvider.new.tracer
    yielded = nil

    value = Telemetry.in_span("auth.sign_in", attributes: { "auth.method" => "password" }, tracer: tracer) do |span|
      yielded = span
      Telemetry.record(span, "auth.outcome" => "ok")
      :the_block
    end

    assert_equal :the_block, value
    assert_not yielded.recording?
    assert_empty @exporter.finished_spans
  end
end
