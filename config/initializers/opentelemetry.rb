# Traces every request/query/HTTP call automatically (Rack, ActionPack,
# ActiveRecord, Net::HTTP, pg -- whatever `opentelemetry-instrumentation-all`
# finds actually loaded; instrumentation for a gem this app doesn't use is a
# harmless no-op, not an error).
#
# Exporter picked per environment, in order:
#   1. test        -> in-memory, so a test can assert on what got recorded
#      (Rails.application.config.x.otel_test_exporter) without printing
#      anything or needing a network call.
#   2. OTEL_EXPORTER_OTLP_ENDPOINT set -> OTLP, batched -- point this at a
#      real backend (e.g. Honeycomb) by setting that one env var, no code or
#      gem change needed; the otlp exporter gem is already bundled.
#   3. otherwise (dev, and production until an endpoint is configured)
#      -> console, printed immediately (SimpleSpanProcessor, not batched) so
#      a span shows up in the log right after the request that created it.
require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/all"

# The SDK's own default is INFO, which logs one line per instrumentation
# library it installs (Rack, ActiveRecord, PG, ...) on every single boot --
# console noise on every dev server start, every console, every test run.
# `OTEL_LOG_LEVEL` still overrides this for anyone who wants it back.
OpenTelemetry.logger = Logger.new($stdout, level: ENV.fetch("OTEL_LOG_LEVEL", "WARN"))

exporter =
  if Rails.env.test?
    OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
  elsif ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present?
    OpenTelemetry::Exporter::OTLP::Exporter.new
  else
    OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
  end

processor_class =
  if exporter.is_a?(OpenTelemetry::Exporter::OTLP::Exporter)
    OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor
  else
    OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor
  end

OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "contentspiel")
  c.add_span_processor(processor_class.new(exporter))
  c.use_all
end

# So a test can retrieve the very exporter the SDK is actually using --
# `Rails.application.config.x` is Rails' own namespace for exactly this kind
# of app-specific setting, kept off the main config object.
Rails.application.config.x.otel_test_exporter = exporter if Rails.env.test?
