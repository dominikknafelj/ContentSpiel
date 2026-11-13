require "test_helper"

# The leaked-password lookup against Have I Been Pwned's range API: only
# the hash's five-character prefix is sent, the answer's suffixes are
# compared here, the switch defaults by environment, and a misbehaving
# service fails open with one line that holds no part of the password.
class SignIn::Password::LeakedTest < ActiveSupport::TestCase
  include LogCapture

  LEAKED = "planted-Leaked-password-1".freeze
  CLEAN = "planted-Clean-password-2".freeze
  ON = { "LEAKED_PASSWORD_CHECK" => "on" }.freeze

  setup do
    @exporter = Rails.application.config.x.otel_test_exporter
    @exporter.reset
    @range = SignIn::Password::Leaked.method(:range)
  end

  def digest(password) = Digest::SHA1.hexdigest(password).upcase

  # The real `range` (taken before any test replaces it), sent to `base`
  # rather than the service.
  def range_at(base)
    original = @range
    ->(prefix, url: nil) { original.call(prefix, url: "#{base}/range/") }
  end

  def check_at(base, password, env: ON)
    with_singleton_override(SignIn::Password::Leaked, :range, range_at(base)) { SignIn::Password::Leaked.check(password, env: env) }
  end

  # What a span says: its name, its attributes and its events', as text.
  def said(span)
    [ span.name, *span.attributes.to_h.flatten, *Array(span.events).flat_map { |event| [ event.name, *event.attributes.to_h.flatten ] } ].join(" ")
  end

  test "a password whose suffix is listed with a count is leaked, one at count 0 is clean, and only the five-character prefix is asked for" do
    body = [ *SignInHelper::RANGE_UNRELATED, "#{digest(LEAKED)[5..]}:3", "#{digest(CLEAN)[5..]}:0" ].join("\r\n")

    with_http_stub(body: body) do |base, requests|
      assert_equal :leaked, check_at(base, LEAKED)
      assert_equal :clean, check_at(base, CLEAN)

      assert_equal [ "GET /range/#{digest(LEAKED)[0, 5]} HTTP/1.1", "GET /range/#{digest(CLEAN)[0, 5]} HTTP/1.1" ], requests.map(&:line)
      assert requests.all? { |request| request.body.empty? }
    end

    with_leaked_password_check(leaked: [ LEAKED ]) do
      assert_equal :leaked, SignIn::Password::Leaked.check(LEAKED)
      assert_equal :clean, SignIn::Password::Leaked.check(CLEAN)
    end
    assert_equal [ digest(LEAKED)[0, 5], digest(CLEAN)[0, 5] ], leaked_password_requests

    assert_raises(ArgumentError) { @range.call("abcde") }
    assert_raises(ArgumentError) { @range.call(digest(LEAKED)[0, 6]) }
  end

  test "off, exactly, turns the check off and sends nothing; any other value leaves it on, and unset it follows the environment" do
    with_leaked_password_check(leaked: [ LEAKED ]) do
      assert_equal :off, SignIn::Password::Leaked.check(LEAKED, env: { "LEAKED_PASSWORD_CHECK" => "off" })
      assert_empty leaked_password_requests

      [ "on", "OFF", "0", "of", "yes" ].each do |value|
        assert_equal :leaked, SignIn::Password::Leaked.check(LEAKED, env: { "LEAKED_PASSWORD_CHECK" => value }), value
      end
      assert_equal 5, leaked_password_requests.size

      [ {}, { "LEAKED_PASSWORD_CHECK" => "" }, { "LEAKED_PASSWORD_CHECK" => " " } ].each do |unset|
        assert_equal :off, SignIn::Password::Leaked.check(LEAKED, env: unset), "unset is off outside production: #{unset}"
        production = ActiveSupport::EnvironmentInquirer.new("production")
        with_singleton_override(Rails, :env, -> { production }) do
          assert_equal :leaked, SignIn::Password::Leaked.check(LEAKED, env: unset), "unset is on in production: #{unset}"
        end
      end
    end

    assert_equal :off, SignIn::Password::Leaked.check(LEAKED), "the suite runs with the variable unset"
  end

  test "a 503, a timeout, a refused connection and an HTML page at 200 are each unavailable, and the line names the class or the status" do
    logs = []
    # Under a request's span, as in the application: a CLIENT root is
    # dropped by the sampler.
    Telemetry.tracer.in_span("probe", kind: :server) do
      with_http_stub(status: 503, body: "Service Unavailable") do |base|
        logs << capture_log { assert_equal :unavailable, check_at(base, LEAKED) }
      end

      logs << capture_log do
        with_leaked_password_check(unavailable: Net::ReadTimeout.new) { assert_equal :unavailable, SignIn::Password::Leaked.check(LEAKED) }
      end

      logs << capture_log { assert_equal :unavailable, check_at("http://127.0.0.1:#{SmtpStub.closed_port}", LEAKED) }

      with_http_stub(body: "<html><body>Sign in to the hotel's Wi-Fi</body></html>", content_type: "text/html") do |base|
        logs << capture_log { assert_equal :unavailable, check_at(base, LEAKED) }
      end
    end

    assert_equal [
      [ "[ContentSpiel] The leaked-password check could not be made: HTTP 503" ],
      [ "[ContentSpiel] The leaked-password check could not be made: Net::ReadTimeout" ],
      [ "[ContentSpiel] The leaked-password check could not be made: Errno::ECONNREFUSED" ],
      [ "[ContentSpiel] The leaked-password check could not be made: SignIn::Password::Leaked::Unavailable (an answer that is not the range's lines)" ]
    ], logs.map { |log| log.lines(chomp: true) }

    spans = @exporter.finished_spans.select { |span| span.name == "auth.leaked_password" }
    assert_equal [
      { "server.address" => "api.pwnedpasswords.com", "auth.leaked_password.result" => "unavailable", "error.type" => "503", "http.response.status_code" => 503 },
      { "server.address" => "api.pwnedpasswords.com", "auth.leaked_password.result" => "unavailable", "error.type" => "Net::ReadTimeout" },
      { "server.address" => "api.pwnedpasswords.com", "auth.leaked_password.result" => "unavailable", "error.type" => "Errno::ECONNREFUSED" },
      { "server.address" => "api.pwnedpasswords.com", "auth.leaked_password.result" => "unavailable", "error.type" => "SignIn::Password::Leaked::Unavailable" }
    ], spans.map { |span| span.attributes.to_h }
    assert spans.all? { |span| span.kind == :client }

    hex = digest(LEAKED)
    written = logs.join + @exporter.finished_spans.map { |span| said(span) }.join(" ")
    [ LEAKED, hex, hex.downcase, hex[0, 5], hex[0, 5].downcase, hex[5..], hex[5..].downcase ].each do |secret|
      assert_not_includes written, secret
    end
  end

  test "the request asks for padding and names ContentSpiel as its agent" do
    with_http_stub(body: "#{digest(LEAKED)[5..]}:1") do |base, requests|
      assert_equal :leaked, check_at(base, LEAKED)

      assert_equal "true", requests.first.headers["add-padding"]
      assert_equal "ContentSpiel/#{ContentSpiel::VERSION}", requests.first.headers["user-agent"]
    end
  end

  test "range runs untraced: no span holds the prefix" do
    prefix = digest(LEAKED)[0, 5]

    with_http_stub(body: "#{digest(LEAKED)[5..]}:1") do |base|
      port = URI(base).port.to_s

      # The instrumentation is installed and would record the path: without
      # `untraced` a plain request to the stub is a span naming it.
      Telemetry.tracer.in_span("probe", kind: :server) { Net::HTTP.get(URI("#{base}/range/#{prefix}")) }
      assert @exporter.finished_spans.any? { |span| span.name != "probe" && said(span).include?(prefix) },
        "the control call is recorded: #{@exporter.finished_spans.map(&:name)}"
      @exporter.reset

      Telemetry.tracer.in_span("probe", kind: :server) { assert_equal :leaked, check_at(base, LEAKED) }

      assert_equal %w[auth.leaked_password probe], @exporter.finished_spans.map(&:name).sort
      text = @exporter.finished_spans.map { |span| said(span) }.join(" ")
      assert_not_includes text, prefix
      assert_not_includes text, port
    end
  end
end
