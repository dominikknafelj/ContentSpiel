require "test_helper"

# No span carries a query string, and so none carries a password-reset token
# handed in one. The words standing for a token here are plain words on
# purpose.
class Telemetry::PathScrubberTest < ActiveSupport::TestCase
  ADMIN = ContentSpiel::ADMIN_PATH
  FILTERED = "[FILTERED]".freeze

  setup do
    @exporter = Rails.application.config.x.otel_test_exporter
    @exporter.reset
  end

  # No query string leaves in a span, whatever its parameters are called: a
  # note's quote travels in one, and a request answered before a controller
  # (a redirect in the routes, a throttle) keeps it as it was sent.
  test "an attribute's query is cut from an address and replaced where it stands alone" do
    {
      [ "url.query", "note_quote=some+private+words&x=1" ] => FILTERED,
      [ "url.query", "" ] => "",
      [ "http.target", "/#{ADMIN}/pages/12?note_quote=some+private+words" ] => "/#{ADMIN}/pages/12",
      [ "http.target", "/#{ADMIN}/password/edit?token=abc123#y" ] => "/#{ADMIN}/password/edit",
      # The single sign-on callback's query is an authorization code and its state.
      [ "url.query", "code=some-code&state=some-state" ] => FILTERED,
      [ "http.target", "/#{ADMIN}/sign-in/sso/callback?code=some-code&state=some-state" ] => "/#{ADMIN}/sign-in/sso/callback",
      [ "url.full", "https://example.org/#{ADMIN}/sign-in/sso/callback?code=some-code&state=some-state" ] => "https://example.org/#{ADMIN}/sign-in/sso/callback",
      [ "http.target", "/up" ] => "/up",
      [ "url.full", "https://example.org/en/blog?note_quote=some+private+words" ] => "https://example.org/en/blog",
      [ "url.full", "https://example.org/#{ADMIN}/password/edit?token=abc123" ] => "https://example.org/#{ADMIN}/password/edit",
      [ "http.url", "https://example.org/?q=some+private+words" ] => "https://example.org/",
      [ "url.path", "/#{ADMIN}/password/edit" ] => "/#{ADMIN}/password/edit",
      [ "url.path", "/a?b" ] => "/a?b",
      [ "http.route", "/#{ADMIN}/password/edit?x=1" ] => "/#{ADMIN}/password/edit?x=1",
      [ "url.query", nil ] => nil,
      [ "http.target", 12 ] => 12
    }.each do |(key, value), scrubbed|
      if scrubbed.nil?
        assert_nil Telemetry::PathScrubber.scrub_attribute(key, value)
      else
        assert_equal scrubbed, Telemetry::PathScrubber.scrub_attribute(key, value), "#{key} #{value.inspect}"
      end
    end
  end

  test "a span that starts with a query holds none, on the span itself and in what is exported" do
    seen = nil
    started_with = {
      "url.path" => "/#{ADMIN}/pages/12",
      "url.query" => "note_quote=some+private+words",
      "http.target" => "/#{ADMIN}/pages/12?note_quote=some+private+words"
    }
    tracer.in_span("request", kind: :server, attributes: started_with) { |span| seen = span.attributes }

    scrubbed = { "url.path" => "/#{ADMIN}/pages/12", "url.query" => FILTERED, "http.target" => "/#{ADMIN}/pages/12" }
    assert_equal scrubbed, seen
    assert_equal scrubbed, exported.attributes
  end

  test "an attribute set after the start is scrubbed in what is exported, each of the five" do
    tracer.in_span("request", kind: :server) do |span|
      span.set_attribute("url.path", "/#{ADMIN}/password/edit")
      span.set_attribute("url.query", "note_quote=some+private+words")
      span.set_attribute("http.target", "/#{ADMIN}/password/edit?token=abc123")
      span.set_attribute("url.full", "https://example.org/#{ADMIN}/password/edit?token=abc123")
      span.set_attribute("http.url", "https://example.org/#{ADMIN}/password/edit")
      span.set_attribute("http.route", "/#{ADMIN}/password/edit")
    end

    assert_equal(
      {
        "url.path" => "/#{ADMIN}/password/edit",
        "url.query" => FILTERED,
        "http.target" => "/#{ADMIN}/password/edit",
        "url.full" => "https://example.org/#{ADMIN}/password/edit",
        "http.url" => "https://example.org/#{ADMIN}/password/edit",
        "http.route" => "/#{ADMIN}/password/edit"
      },
      exported.attributes
    )
    assert_predicate exported.attributes, :frozen?
  end

  test "a span with nothing to scrub is exported as it is" do
    tracer.in_span("request", kind: :server, attributes: { "url.path" => "/#{ADMIN}/pages" }) { }
    tracer.in_span("bare", kind: :server) { }

    paths, bare = @exporter.finished_spans
    assert_equal({ "url.path" => "/#{ADMIN}/pages" }, paths.attributes)
    assert_equal "bare", bare.name
  end

  test "the exporter's wrapper hands on what it is not asked to change" do
    inner = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
    wrapper = Telemetry::PathScrubber::Exporter.new(inner)

    assert_equal OpenTelemetry::SDK::Trace::Export::SUCCESS, wrapper.force_flush
    assert_equal OpenTelemetry::SDK::Trace::Export::SUCCESS, wrapper.shutdown
    assert_equal OpenTelemetry::SDK::Trace::Export::FAILURE, wrapper.export([]), "the inner exporter was shut down through the wrapper"
  end

  private
    # Every span here is started as a request's (`kind: :server`): a root of
    # any other kind is dropped by `Telemetry::WorkSampler` and would never
    # reach the scrubber or the exporter.
    def tracer = OpenTelemetry.tracer_provider.tracer("path-scrubber-test")

    def exported
      assert_equal 1, @exporter.finished_spans.size
      @exporter.finished_spans.first
    end
end
