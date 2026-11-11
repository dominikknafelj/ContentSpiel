require "test_helper"

# Turnstile's verification on the server: on only with both keys, junk
# refused without a call, Cloudflare's answer read, and its outage failing
# open with one line that names a class and nothing sent.
class SignIn::BotCheckTest < ActiveSupport::TestCase
  include LogCapture

  TOKEN = "XXXX.DUMMY.TOKEN.XXXX-planted-token".freeze
  ADDRESS = "203.0.113.7".freeze
  HOST = SignInHelper::BOT_CHECK_HOSTNAME
  YES = %({"success":true,"hostname":"#{HOST}","action":"sign_in"}).freeze
  SITE_KEY = SignInHelper::BOT_CHECK_KEYS.fetch("TURNSTILE_SITE_KEY")
  SECRET_KEY = SignInHelper::BOT_CHECK_KEYS.fetch("TURNSTILE_SECRET_KEY")

  setup do
    @exporter = Rails.application.config.x.otel_test_exporter
    @exporter.reset
    @siteverify = SignIn::BotCheck.method(:siteverify)
  end

  def check = SignIn::BotCheck.current

  # What a span says: its name, its attributes and its events', as text
  # (its ids and timestamps are figures that could hold any digits).
  def said(span)
    [ span.name, *span.attributes.to_h.flatten, *Array(span.events).flat_map { |event| [ event.name, *event.attributes.to_h.flatten ] } ].join(" ")
  end

  # The real `siteverify` (taken before any test replaces it), sent to the
  # stub server at `base` rather than Cloudflare.
  def siteverify_at(base)
    original = @siteverify
    ->(form, url: nil) { original.call(form, url: "#{base}/siteverify") }
  end

  test "one key without the other is no bot check, and the boot line names the missing variable" do
    both = { "TURNSTILE_SITE_KEY" => SITE_KEY, "TURNSTILE_SECRET_KEY" => SECRET_KEY }
    assert_equal SITE_KEY, SignIn::BotCheck.current(both).site_key
    assert_nil SignIn::BotCheck.missing_variable(both)

    assert_nil SignIn::BotCheck.current({})
    assert_nil SignIn::BotCheck.missing_variable({}), "a site that set neither asked for no check"

    [ nil, "", "  " ].each do |unset|
      site_only = { "TURNSTILE_SITE_KEY" => SITE_KEY, "TURNSTILE_SECRET_KEY" => unset }
      assert_nil SignIn::BotCheck.current(site_only)
      assert_equal "TURNSTILE_SECRET_KEY", SignIn::BotCheck.missing_variable(site_only)

      secret_only = { "TURNSTILE_SITE_KEY" => unset, "TURNSTILE_SECRET_KEY" => SECRET_KEY }
      assert_nil SignIn::BotCheck.current(secret_only)
      assert_equal "TURNSTILE_SITE_KEY", SignIn::BotCheck.missing_variable(secret_only)
    end

    assert_nil SignIn::BotCheck.current, "the suite runs with neither key"
  end

  test "a token that is no String or is over 2,048 characters is refused without asking Cloudflare" do
    with_bot_check(:passed) do
      [ [ "x" ], { "token" => "x" }, nil, "", "a" * 2049 ].each do |token|
        assert_equal :failed, check.verify(token, address: ADDRESS, hostname: HOST), token.inspect.truncate(40)
      end
      assert_equal :passed, check.verify("a" * 2048, address: ADDRESS, hostname: HOST)
    end

    assert_equal 1, bot_check_requests.size, "only the token of 2,048 characters was sent"
  end

  test "Cloudflare's yes is passed, its no is failed, and internal-error or a network error is unavailable with one line naming the class" do
    # Under a request's span, as in the application: a CLIENT root is
    # dropped by the sampler.
    Telemetry.tracer.in_span("probe", kind: :server) do
      with_bot_check(:passed) { assert_equal :passed, check.verify(TOKEN, address: ADDRESS, hostname: HOST) }
      with_bot_check(:failed) { assert_equal :failed, check.verify(TOKEN, address: ADDRESS, hostname: HOST) }

      log = capture_log do
        with_bot_check(:unavailable) { assert_equal :unavailable, check.verify(TOKEN, address: ADDRESS, hostname: HOST) }
      end
      assert_equal [ "[ContentSpiel] The bot check could not be verified: Errno::ECONNREFUSED" ], log.lines(chomp: true)

      internal = ->(_form, url: nil) { { "success" => false, "error-codes" => [ "internal-error" ] } }
      log = capture_log do
        with_bot_check do
          with_singleton_override(SignIn::BotCheck, :siteverify, internal) do
            assert_equal :unavailable, check.verify(TOKEN, address: ADDRESS, hostname: HOST)
          end
        end
      end
      assert_equal [ "[ContentSpiel] The bot check could not be verified: internal-error" ], log.lines(chomp: true)

      with_http_stub(status: 503, body: "busy") do |base|
        log = capture_log do
          with_bot_check do
            with_singleton_override(SignIn::BotCheck, :siteverify, siteverify_at(base)) do
              assert_equal :unavailable, check.verify(TOKEN, address: ADDRESS, hostname: HOST)
            end
          end
        end
        assert_equal [ "[ContentSpiel] The bot check could not be verified: HTTP 503" ], log.lines(chomp: true)
      end

      with_http_stub(body: "<html>a captive portal</html>", content_type: "text/html") do |base|
        log = capture_log do
          with_bot_check do
            with_singleton_override(SignIn::BotCheck, :siteverify, siteverify_at(base)) do
              assert_equal :unavailable, check.verify(TOKEN, address: ADDRESS, hostname: HOST)
            end
          end
        end
        assert_equal [ "[ContentSpiel] The bot check could not be verified: JSON::ParserError" ], log.lines(chomp: true)
      end
    end

    results = @exporter.finished_spans.select { |span| span.name == "auth.bot_check" }.map { |span| span.attributes.to_h }
    assert_equal [
      { "server.address" => "challenges.cloudflare.com", "auth.bot_check.result" => "passed", "http.response.status_code" => 200 },
      { "server.address" => "challenges.cloudflare.com", "auth.bot_check.result" => "failed", "http.response.status_code" => 200 },
      { "server.address" => "challenges.cloudflare.com", "auth.bot_check.result" => "unavailable", "error.type" => "Errno::ECONNREFUSED" },
      { "server.address" => "challenges.cloudflare.com", "auth.bot_check.result" => "unavailable", "error.type" => "internal-error", "http.response.status_code" => 200 },
      { "server.address" => "challenges.cloudflare.com", "auth.bot_check.result" => "unavailable", "error.type" => "503", "http.response.status_code" => 503 },
      { "server.address" => "challenges.cloudflare.com", "auth.bot_check.result" => "unavailable", "error.type" => "JSON::ParserError" }
    ], results
    assert @exporter.finished_spans.select { |span| span.name == "auth.bot_check" }.all? { |span| span.kind == :client }
    spans = @exporter.finished_spans.map { |span| said(span) }.join(" ")
    [ TOKEN, SECRET_KEY ].each { |secret| assert_not_includes spans, secret }
  end

  test "Cloudflare's yes for another host or another action is failed" do
    answers = {
      { "success" => true, "hostname" => "other.example", "action" => "sign_in" } => :failed,
      { "success" => true, "hostname" => HOST, "action" => "newsletter" } => :failed,
      { "success" => true, "hostname" => HOST } => :failed,
      { "success" => true, "action" => "sign_in" } => :failed,
      { "success" => true, "hostname" => HOST.upcase, "action" => "sign_in" } => :passed
    }

    Telemetry.tracer.in_span("probe", kind: :server) do
      with_bot_check do
        answers.each do |answer, expected|
          with_singleton_override(SignIn::BotCheck, :siteverify, ->(_form, url: nil) { answer }) do
            assert_equal expected, check.verify(TOKEN, address: ADDRESS, hostname: HOST), answer.inspect
          end
        end
        assert_equal :failed, check.verify(TOKEN, address: ADDRESS, hostname: "other.example"), "the request's host is the one compared"
      end
    end

    assert_equal %w[failed failed failed failed passed failed],
      @exporter.finished_spans.select { |span| span.name == "auth.bot_check" }.map { |span| span.attributes["auth.bot_check.result"] }
  end

  test "a code of the site's is unavailable with one line naming it, and a wrong, expired or replayed token is failed" do
    site_codes = {
      "invalid-input-secret" => "invalid-input-secret",
      "missing-input-secret" => "missing-input-secret",
      "bad-request" => "bad-request",
      "internal-error" => "internal-error",
      "some-new-code" => "some-new-code",
      "<script>#{SECRET_KEY}</script>" => "an unknown error code"
    }
    site_codes.each do |code, named|
      answer = { "success" => false, "error-codes" => [ "invalid-input-response", code ] }
      log = capture_log do
        with_bot_check do
          with_singleton_override(SignIn::BotCheck, :siteverify, ->(_form, url: nil) { answer }) do
            assert_equal :unavailable, check.verify(TOKEN, address: ADDRESS, hostname: HOST), code
          end
        end
      end
      assert_equal [ "[ContentSpiel] The bot check could not be verified: #{named}" ], log.lines(chomp: true)
      assert_not_includes log, SECRET_KEY
    end

    [ [ "invalid-input-response" ], [ "timeout-or-duplicate" ], [] ].each do |codes|
      answer = { "success" => false, "error-codes" => codes }
      log = capture_log do
        with_bot_check do
          with_singleton_override(SignIn::BotCheck, :siteverify, ->(_form, url: nil) { answer }) do
            assert_equal :failed, check.verify(TOKEN, address: ADDRESS, hostname: HOST), codes.inspect
          end
        end
      end
      assert_empty log, "a token Cloudflare turned down is the visitor's, and writes no line"
    end
  end

  test "a 200 with an empty body is unavailable" do
    with_http_stub(body: "") do |base|
      log = capture_log do
        with_bot_check do
          with_singleton_override(SignIn::BotCheck, :siteverify, siteverify_at(base)) do
            assert_equal :unavailable, check.verify(TOKEN, address: ADDRESS, hostname: HOST)
          end
        end
      end
      assert_equal [ "[ContentSpiel] The bot check could not be verified: JSON::ParserError" ], log.lines(chomp: true)
    end
  end

  test "the form sent is the secret, the token and the address, and nothing else" do
    with_bot_check { check.verify(TOKEN, address: ADDRESS, hostname: HOST) }
    assert_equal [ { "secret" => SECRET_KEY, "response" => TOKEN, "remoteip" => ADDRESS } ], bot_check_requests

    with_http_stub(body: YES, content_type: "application/json") do |base, requests|
      SignIn::BotCheck.siteverify({ "secret" => SECRET_KEY, "response" => TOKEN, "remoteip" => ADDRESS }, url: "#{base}/turnstile/v0/siteverify")

      assert_equal [ "POST /turnstile/v0/siteverify HTTP/1.1" ], requests.map(&:line)
      assert_equal "application/x-www-form-urlencoded", requests.first.headers["content-type"]
      assert_equal({ "secret" => [ SECRET_KEY ], "response" => [ TOKEN ], "remoteip" => [ ADDRESS ] }, CGI.parse(requests.first.body))
    end
  end

  test "siteverify runs untraced: no span of the HTTP instrumentation is recorded for it" do
    with_http_stub(body: YES, content_type: "application/json") do |base|
      port = URI(base).port.to_s

      # The instrumentation is installed and would record this call: without
      # `untraced` a plain request to the stub is a span naming its port.
      Telemetry.tracer.in_span("probe", kind: :server) { Net::HTTP.get(URI("#{base}/siteverify")) }
      assert @exporter.finished_spans.any? { |span| span.name != "probe" && said(span).include?(port) },
        "the control call is recorded: #{@exporter.finished_spans.map(&:name)}"
      @exporter.reset

      with_bot_check do
        with_singleton_override(SignIn::BotCheck, :siteverify, siteverify_at(base)) do
          Telemetry.tracer.in_span("probe", kind: :server) { assert_equal :passed, check.verify(TOKEN, address: ADDRESS, hostname: HOST) }
        end
      end

      assert_equal %w[auth.bot_check probe], @exporter.finished_spans.map(&:name).sort
      assert_not @exporter.finished_spans.any? { |span| said(span).include?(port) }, "no span names the stub's port"
    end
  end
end
