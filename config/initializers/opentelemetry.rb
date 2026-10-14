# Traces every request/query/HTTP call automatically (Rack, ActionPack,
# ActiveRecord, Net::HTTP, pg -- whatever `opentelemetry-instrumentation-all`
# finds actually loaded; instrumentation for a gem this app doesn't use is a
# harmless no-op, not an error).
#
# Where the spans go is `Telemetry.exporter_kind` (lib/telemetry.rb), first
# match first:
#   1. test        -> in-memory, so a test can assert on what got recorded
#      (Rails.application.config.x.otel_test_exporter) without printing
#      anything or needing a network call.
#   2. OTEL_EXPORTER_OTLP_ENDPOINT set -> OTLP, batched -- point this at a
#      real backend (e.g. Honeycomb) by setting that one env var, no code or
#      gem change needed; the otlp exporter gem is already bundled.
#      (OTEL_EXPORTER_OTLP_TRACES_ENDPOINT, which the exporter reads ahead
#      of it, counts the same.)
#   3. OTEL_CONSOLE=1 -> console, printed immediately (SimpleSpanProcessor,
#      not batched) so a span shows up in the terminal right after the
#      request that created it. For a developer who wants to look, in any
#      environment, and only when asked for by that one value.
#   4. otherwise (development and production alike) -> nothing. The SDK is
#      not configured at all: no instrumentation is installed, no span is
#      made, and `OpenTelemetry.tracer_provider` stays the API's own no-op,
#      which anything that asks it for a tracer can still call.
#
# Case 4 used to be the console. A production container with no endpoint
# printed every span to its log: about 49,000 lines for 60 requests, and in
# them the path of every request, a password-reset token included. Hence the
# two rules of this file: nothing is printed unless asked, and whatever is
# exported, printed or sent, goes through `Telemetry::PathScrubber` first.
# And a third, since the first day spans went to a backend: what is recorded
# is the work a request or a job caused, never the background's polling
# (`Telemetry::WorkSampler`, assigned at the end of this file).
require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/all"

# The SDK's own default is INFO, which logs one line per instrumentation
# library it installs (Rack, ActiveRecord, PG, ...) on every single boot --
# console noise on every dev server start, every console, every test run.
# `OTEL_LOG_LEVEL` still overrides this for anyone who wants it back.
OpenTelemetry.logger = Logger.new($stdout, level: ENV.fetch("OTEL_LOG_LEVEL", "WARN"))

kind = Telemetry.exporter_kind(ENV, Rails.env)

exporter =
  case kind
  when :memory then OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
  when :otlp then OpenTelemetry::Exporter::OTLP::Exporter.new
  when :console then OpenTelemetry::SDK::Trace::Export::ConsoleSpanExporter.new
  end

unless kind == :none
  processor_class =
    if kind == :otlp
      OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor
    else
      OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor
    end

  OpenTelemetry::SDK.configure do |c|
    c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "contentspiel")

    # No span leaves with a password-reset token in its address, or with a
    # query string (a note's quote travels in one), twice over:
    # the scrubber's processor comes FIRST, so the attributes a span starts
    # with are clean before any other processor sees it, and the exporter is
    # wrapped, because an attribute set after the start can only be rewritten
    # in the copy that is exported (lib/telemetry/path_scrubber.rb).
    c.add_span_processor(Telemetry::PathScrubber::Processor.new)
    c.add_span_processor(processor_class.new(Telemetry::PathScrubber::Exporter.new(exporter)))

    c.use_all(
      # Rake instrumentation traces every task invocation, including `bin/rails
      # db:migrate`/`sitemap:create`/the test runner's own setup tasks -- with
      # the console exporter this is hundreds of SpanData structs dumped to the
      # terminal for one ordinary CLI command, not a request this app actually
      # wants visibility into.
      "OpenTelemetry::Instrumentation::Rake" => { enabled: false },

      # Segfaults `bin/rails test`'s parallel workers: `parallelize` forks the
      # test process, and this instrumentation's wrapping of PG::Connection
      # doesn't survive the fork cleanly -- a *child* process crashes inside
      # libpq's connect_start with a SIGSEGV the moment it opens its own new
      # connection, reproduced consistently across multiple runs. ActiveRecord
      # instrumentation (still on) already covers every query made through
      # ActiveRecord, which is the entire app; this only adds coverage for a
      # raw PG::Connection used outside ActiveRecord, which nothing here does.
      "OpenTelemetry::Instrumentation::PG" => { enabled: false }
    )
  end

  # Only a trace that begins with a request or with a job being performed is
  # recorded; one that begins in Solid Cable's or Solid Queue's polling, or
  # in their heartbeats, is dropped whole, before any processor sees it
  # (lib/telemetry/work_sampler.rb says why it is a sampler and why by kind).
  # That was about 820,000 spans a day on an idle site. `configure` takes no
  # sampler, so it is assigned to the provider `configure` made, before any
  # span can start (Puma, Solid Queue and Solid Cable start their threads
  # after the initializers). For all three exporters alike, so that what a
  # test records and what the console prints are what a backend is sent.
  OpenTelemetry.tracer_provider.sampler = Telemetry::WorkSampler.sampler
end

# So a test can retrieve the very exporter the SDK is actually using (the
# one inside the scrubber's wrapper, so what a test reads is what a backend
# would be sent) -- `Rails.application.config.x` is Rails' own namespace for
# exactly this kind of app-specific setting, kept off the main config object.
Rails.application.config.x.otel_test_exporter = exporter if Rails.env.test?
