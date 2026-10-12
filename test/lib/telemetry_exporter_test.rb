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
  # with the answer. Two real boots of the development environment (nothing
  # of the database is read): with neither variable the SDK is never
  # configured, so the API's own no-op provider is still in place and
  # nothing is printed but the one line asked for; with OTEL_CONSOLE=1 the
  # SDK's provider is there.
  test "a development boot with neither variable configures no SDK and prints nothing, and OTEL_CONSOLE=1 configures it" do
    script = "puts OpenTelemetry.tracer_provider.class.name"

    quiet, status = boot_development(script, {})
    assert status.success?, quiet
    assert_equal "OpenTelemetry::Internal::ProxyTracerProvider\n", quiet

    asked, status = boot_development(script, CONSOLE)
    assert status.success?, asked
    assert_equal "OpenTelemetry::SDK::Trace::TracerProvider", asked.lines.last.to_s.chomp
  end

  private
    def boot_development(script, variables)
      env = {
        "RAILS_ENV" => "development",
        "OTEL_EXPORTER_OTLP_ENDPOINT" => nil,
        "OTEL_CONSOLE" => nil,
        "OTEL_LOG_LEVEL" => nil
      }.merge(variables)

      Bundler.with_original_env do
        Open3.capture2e(env, Rails.root.join("bin/rails").to_s, "runner", script, chdir: Rails.root.to_s)
      end
    end
end
