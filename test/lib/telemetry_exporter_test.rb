require "test_helper"
require "open3"

# Which exporter the boot picks (`config/initializers/opentelemetry.rb`), as
# a table: the test environment records in memory, an OTLP endpoint sends
# there, `OTEL_CONSOLE=1` prints, and everything else is nothing at all. The
# last row is the one that matters: production used to print every span to
# its log until an endpoint was configured.
class TelemetryExporterTest < ActiveSupport::TestCase
  ENDPOINT = { "OTEL_EXPORTER_OTLP_ENDPOINT" => "https://collector.example.org" }.freeze
  CONSOLE = { "OTEL_CONSOLE" => "1" }.freeze

  test "the test environment records in memory, whatever is set" do
    assert_equal :memory, Telemetry.exporter_kind({}, "test")
    assert_equal :memory, Telemetry.exporter_kind(ENDPOINT.merge(CONSOLE), "test")
  end

  test "an OTLP endpoint is where the spans go, in production and in development" do
    assert_equal :otlp, Telemetry.exporter_kind(ENDPOINT, "production")
    assert_equal :otlp, Telemetry.exporter_kind(ENDPOINT, "development")
  end

  # The OTLP exporter reads the traces' own variable by itself, ahead of
  # the general one, so either is "an endpoint is configured".
  test "the traces' own endpoint variable is an endpoint too: either, and both" do
    traces = { "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" => "https://collector.example.org/v1/traces" }

    assert_equal :otlp, Telemetry.exporter_kind(traces, "production")
    assert_equal :otlp, Telemetry.exporter_kind(traces, "development")
    assert_equal :otlp, Telemetry.exporter_kind(traces.merge(ENDPOINT), "production")
    assert_equal :otlp, Telemetry.exporter_kind(traces.merge(CONSOLE), "production")
    assert_equal :otlp, Telemetry.exporter_kind(traces.merge("OTEL_EXPORTER_OTLP_ENDPOINT" => " "), "production")
    assert_equal :none, Telemetry.exporter_kind({ "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" => " " }, "production")
    assert_equal :memory, Telemetry.exporter_kind(traces, "test")
  end

  test "an endpoint wins over OTEL_CONSOLE" do
    assert_equal :otlp, Telemetry.exporter_kind(ENDPOINT.merge(CONSOLE), "production")
    assert_equal :otlp, Telemetry.exporter_kind(ENDPOINT.merge(CONSOLE), "development")
  end

  test "OTEL_CONSOLE=1 prints the spans, and only the value 1 asks for it" do
    assert_equal :console, Telemetry.exporter_kind(CONSOLE, "development")
    assert_equal :console, Telemetry.exporter_kind(CONSOLE, "production")

    [ "", "0", "true", "yes", " 1" ].each do |value|
      assert_equal :none, Telemetry.exporter_kind({ "OTEL_CONSOLE" => value }, "development"), "OTEL_CONSOLE=#{value.inspect}"
    end
  end

  test "with neither variable there is no telemetry, in production and in development" do
    assert_equal :none, Telemetry.exporter_kind({}, "production")
    assert_equal :none, Telemetry.exporter_kind({}, "development")
  end

  test "a blank endpoint is no endpoint" do
    [ "", "   " ].each do |value|
      assert_equal :none, Telemetry.exporter_kind({ "OTEL_EXPORTER_OTLP_ENDPOINT" => value }, "production")
      assert_equal :console, Telemetry.exporter_kind(CONSOLE.merge("OTEL_EXPORTER_OTLP_ENDPOINT" => value), "production")
    end
  end

  test "the environment may be Rails.env itself" do
    assert_equal :memory, Telemetry.exporter_kind({}, Rails.env)
    assert_equal :none, Telemetry.exporter_kind({}, ActiveSupport::EnvironmentInquirer.new("production"))
  end

  # The table above is only what the initializer asks; this is what it does
  # with the answer. Two real boots of the development environment, each
  # making one span and then printing a marker line. With neither variable
  # the SDK is never configured: the API's own no-op provider is still in
  # place and the span is printed nowhere. With OTEL_CONSOLE=1 the SDK's
  # provider is there and the span is in the terminal.
  #
  # The boot is a whole one, so it is not free of the development database:
  # `config/initializers/setup_token.rb` asks `Setup.required?` once the
  # application is up (and goes on without an answer when there is no
  # database). Nothing is written to it, and the test database is not
  # touched. A boot that does not finish is killed and fails the test.
  test "a development boot with neither variable configures no SDK and prints no span, and OTEL_CONSOLE=1 prints it" do
    script = 'OpenTelemetry.tracer_provider.tracer("probe").in_span("probe-span") { }; puts "provider: #{OpenTelemetry.tracer_provider.class.name}"'

    quiet = boot_development(script, {})
    assert_includes quiet.lines(chomp: true), "provider: OpenTelemetry::Internal::ProxyTracerProvider", quiet
    assert_no_match(/SpanData|probe-span/, quiet)

    asked = boot_development(script, CONSOLE)
    assert_includes asked.lines(chomp: true), "provider: OpenTelemetry::SDK::Trace::TracerProvider", asked
    assert_match(/SpanData/, asked)
    assert_match(/name="probe-span"/, asked)
  end

  private
    BOOT_SECONDS = 90

    # What the boot printed, stdout and stderr together. The child is killed
    # when it has not finished in BOOT_SECONDS (a database host that never
    # answers would otherwise hang the suite), and that fails the test.
    def boot_development(script, variables)
      env = {
        "RAILS_ENV" => "development",
        "OTEL_EXPORTER_OTLP_ENDPOINT" => nil,
        "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" => nil,
        "OTEL_CONSOLE" => nil,
        "OTEL_LOG_LEVEL" => nil
      }.merge(variables)

      Bundler.with_original_env do
        Open3.popen2e(env, Rails.root.join("bin/rails").to_s, "runner", script, chdir: Rails.root.to_s) do |input, output, thread|
          input.close
          reader = Thread.new { output.read }

          unless thread.join(BOOT_SECONDS)
            Process.kill("KILL", thread.pid)
            thread.join
            flunk "the development boot did not finish in #{BOOT_SECONDS} seconds"
          end

          reader.value.tap { |printed| assert thread.value.success?, printed }
        end
      end
    end
end
