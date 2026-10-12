require "test_helper"

# No span carries a password-reset token. The token used to be a segment of
# two routes' paths, and the Rack instrumentation records the path of every
# request. The words standing for a token here are plain words on purpose.
class Telemetry::PathScrubberTest < ActiveSupport::TestCase
  ADMIN = ContentSpiel::ADMIN_PATH
  FILTERED = "[FILTERED]".freeze

  setup do
    @exporter = Rails.application.config.x.otel_test_exporter
    @exporter.reset
  end

  def scrub(path, **) = Telemetry::PathScrubber.scrub(path, **)

  test "the token of the edit route is filtered" do
    assert_equal "/#{ADMIN}/password/#{FILTERED}/edit", scrub("/#{ADMIN}/password/abc123/edit")
  end

  test "the token of the update route is filtered" do
    assert_equal "/#{ADMIN}/password/#{FILTERED}", scrub("/#{ADMIN}/password/abc123")
  end

  test "the routes that carry no token are left as they are" do
    [ "/#{ADMIN}/password/edit", "/#{ADMIN}/password/new", "/#{ADMIN}/password",
      "/#{ADMIN}/password/", "/#{ADMIN}/password/new?email=x", "/#{ADMIN}/password/edit/" ].each do |path|
      assert_equal path, scrub(path)
      assert_same path, scrub(path), "an unchanged path is the same string"
    end
  end

  test "any other path is left as it is" do
    [ "/", "/up", "/en/blog/password/abc123/edit", "/#{ADMIN}/account/password", "/#{ADMIN}/passwords/abc123",
      "/#{ADMIN}/pages/12/edit", "/#{ADMIN}x/password/abc123", "/password/abc123/edit" ].each do |path|
      assert_equal path, scrub(path)
    end
  end

  test "a full URL with the token in it is filtered, and its origin and query stay" do
    assert_equal "https://example.org/#{ADMIN}/password/#{FILTERED}/edit",
                 scrub("https://example.org/#{ADMIN}/password/abc123/edit")
    assert_equal "http://localhost:3000/#{ADMIN}/password/#{FILTERED}?x=1",
                 scrub("http://localhost:3000/#{ADMIN}/password/abc123?x=1")
  end

  test "a query string, a format, a trailing slash and doubled slashes do not hide the token" do
    {
      "/#{ADMIN}/password/abc123/edit?x=1" => "/#{ADMIN}/password/#{FILTERED}/edit?x=1",
      "/#{ADMIN}/password/abc123?x=1" => "/#{ADMIN}/password/#{FILTERED}?x=1",
      "/#{ADMIN}/password/abc123/edit.html" => "/#{ADMIN}/password/#{FILTERED}/edit.html",
      "/#{ADMIN}/password/abc123/" => "/#{ADMIN}/password/#{FILTERED}/",
      "//#{ADMIN}//password//abc123/edit/" => "//#{ADMIN}//password//#{FILTERED}/edit/",
      # What a mail program that took a bracket into the link asks for: no
      # route of ours, and the token is in it all the same.
      "/#{ADMIN}/password/abc123/edit)" => "/#{ADMIN}/password/#{FILTERED}/edit)",
      "/#{ADMIN}/password/new/edit" => "/#{ADMIN}/password/#{FILTERED}/edit",
      "/#{ADMIN}/password/edit/edit" => "/#{ADMIN}/password/#{FILTERED}/edit"
    }.each do |path, scrubbed|
      assert_equal scrubbed, scrub(path)
    end
  end

  test "the pattern is built from the admin path, not from a literal" do
    assert_equal "/back-office/password/#{FILTERED}/edit", scrub("/back-office/password/abc123/edit", admin_path: "back-office")
    assert_equal "/cs-studio/password/abc123/edit", scrub("/cs-studio/password/abc123/edit", admin_path: "back-office")
    assert_equal "/a.b/password/#{FILTERED}", scrub("/a.b/password/abc123", admin_path: "a.b")
    assert_equal "/aXb/password/abc123", scrub("/aXb/password/abc123", admin_path: "a.b")
  end

  test "what is not a string is handed back" do
    assert_nil scrub(nil)
    assert_equal 12, scrub(12)
  end

  test "an attribute a span starts with is scrubbed, on the span itself and in what is exported" do
    seen = nil
    tracer.in_span("request", attributes: { "url.path" => "/#{ADMIN}/password/abc123/edit", "other" => "/#{ADMIN}/password/abc123/edit" }) do |span|
      seen = span.attributes["url.path"]
    end

    assert_equal "/#{ADMIN}/password/#{FILTERED}/edit", seen
    assert_equal "/#{ADMIN}/password/#{FILTERED}/edit", exported.attributes["url.path"]
    assert_equal "/#{ADMIN}/password/abc123/edit", exported.attributes["other"], "only the four address attributes are rewritten"
  end

  test "an attribute set after the start is scrubbed in what is exported, each of the four" do
    tracer.in_span("request") do |span|
      span.set_attribute("url.path", "/#{ADMIN}/password/abc123")
      span.set_attribute("http.target", "/#{ADMIN}/password/abc123/edit?x=1")
      span.set_attribute("url.full", "https://example.org/#{ADMIN}/password/abc123/edit")
      span.set_attribute("http.url", "https://example.org/#{ADMIN}/password/abc123")
      span.set_attribute("http.route", "/#{ADMIN}/password/:token/edit")
    end

    assert_equal(
      {
        "url.path" => "/#{ADMIN}/password/#{FILTERED}",
        "http.target" => "/#{ADMIN}/password/#{FILTERED}/edit?x=1",
        "url.full" => "https://example.org/#{ADMIN}/password/#{FILTERED}/edit",
        "http.url" => "https://example.org/#{ADMIN}/password/#{FILTERED}",
        "http.route" => "/#{ADMIN}/password/:token/edit"
      },
      exported.attributes
    )
    assert_predicate exported.attributes, :frozen?
  end

  test "a span with nothing to scrub is exported as it is" do
    tracer.in_span("request", attributes: { "url.path" => "/#{ADMIN}/pages" }) { }
    tracer.in_span("bare") { }

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
    def tracer = OpenTelemetry.tracer_provider.tracer("path-scrubber-test")

    def exported
      assert_equal 1, @exporter.finished_spans.size
      @exporter.finished_spans.first
    end
end
