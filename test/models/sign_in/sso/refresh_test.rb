require "test_helper"

# The daily re-check of an SSO session: its refresh token sent back to the
# provider, which answers that the person is still there (`:ok`, with the
# token it rotated to), is gone (`:revoked`) or could not be asked
# (`:unavailable`).
class SignIn::Sso::RefreshTest < ActiveSupport::TestCase
  include LogCapture

  def refresh(idp) = SignIn::Sso::Refresh.new(provider: idp.provider)

  def spans(&block)
    exporter = Rails.application.config.x.otel_test_exporter
    exporter.reset
    Telemetry.tracer.in_span("probe", kind: :server, &block)
    exporter.finished_spans
  end

  def token_posts(idp) = idp.requests.select { |request| request.path == "/idp/token" }

  test "a refresh answers ok with a rotated token, revoked on invalid_grant or another subject, unavailable when the provider is down" do
    with_fake_idp(refresh_token: "rt-1") do |idp|
      result = refresh(idp).call("rt-1", subject: "sub-1")
      assert_equal [ :ok, "rt-1" ], [ result.status, result.refresh_token ], "the provider rotated nothing: the token given"
      assert_equal({ "grant_type" => "refresh_token", "refresh_token" => "rt-1" }, token_posts(idp).last.params)
      assert token_posts(idp).last.headers["authorization"].start_with?("Basic ")

      idp.rotate_refresh_token("rt-2")
      assert_equal [ :ok, "rt-2" ], refresh(idp).call("rt-1", subject: "sub-1").then { |r| [ r.status, r.refresh_token ] }
      assert_equal [ :revoked, nil ], refresh(idp).call("rt-1", subject: "sub-1").then { |r| [ r.status, r.refresh_token ] },
        "the old token after a rotation is invalid_grant"

      idp.change_identity(subject: "sub-2")
      assert_equal [ :revoked, nil ], refresh(idp).call("rt-2", subject: "sub-1").then { |r| [ r.status, r.refresh_token ] }
      idp.change_identity(subject: "sub-1")
      assert_equal :ok, refresh(idp).call("rt-2", subject: "sub-1").status

      idp.revoke!
      assert_equal :revoked, refresh(idp).call("rt-2", subject: "sub-1").status

      idp.down!
      assert_equal [ :unavailable, nil ], refresh(idp).call("rt-2", subject: "sub-1").then { |r| [ r.status, r.refresh_token ] }
      Rails.cache.clear
      assert_equal :unavailable, refresh(idp).call("rt-2", subject: "sub-1").status, "discovery out of reach too"
    end
  end

  test "a refreshed ID token is not held to the sign-in's age limit, and is still held to exp, aud and its subject" do
    with_fake_idp do |idp|
      now = Time.current.to_i
      issued = now - 26.hours.to_i
      answer = ->(claims) { idp.answer_token_with(body: { "access_token" => "at", "token_type" => "Bearer", "id_token" => idp.id_token(claims) }) }

      answer.call("iat" => issued, "exp" => now + 3600)
      assert_equal :ok, refresh(idp).call("rt-1", subject: "sub-1").status, "the sign-in's token repeated a day later"

      answer.call("iat" => issued, "exp" => issued + 300)
      assert_equal :unavailable, refresh(idp).call("rt-1", subject: "sub-1").status, "expired"
      answer.call("iat" => issued, "exp" => now + 3600, "aud" => "another-client")
      assert_equal :unavailable, refresh(idp).call("rt-1", subject: "sub-1").status, "another audience"
      answer.call("iat" => issued, "exp" => now + 3600, "sub" => "sub-2")
      assert_equal :revoked, refresh(idp).call("rt-1", subject: "sub-1").status, "another subject"
    end
  end

  test "an answer with no ID token is ok, and a 5xx, a body over the limit or of the wrong shape is unavailable" do
    with_fake_idp do |idp|
      idp.answer_token_with(body: { "access_token" => "at", "token_type" => "Bearer" })
      assert_equal [ :ok, "rt-1" ], refresh(idp).call("rt-1", subject: "sub-1").then { |r| [ r.status, r.refresh_token ] }

      [
        { status: 503, body: "down" },
        { status: 500, body: { "error" => "invalid_grant" } },
        { status: 401, body: { "error" => "invalid_client" } },
        { status: 400, body: { "error" => "invalid_request" } },
        { status: 400, body: "invalid_grant" },
        { body: "<html>planted</html>" },
        { body: "[1, 2]" },
        { body: { "padding" => "x" * SignIn::Sso::MAX_BODY } },
        { body: { "refresh_token" => { "a" => "b" } } },
        { body: { "refresh_token" => "" } },
        { body: { "id_token" => [ "x" ] } },
        { body: { "id_token" => "planted.not.a-jwt" } },
        { body: { "id_token" => idp.id_token({}, alg: "none") } },
        { body: { "id_token" => idp.id_token({ "iss" => "https://planted.example.org" }) } },
        { body: { "id_token" => idp.id_token({ "aud" => "planted-other-client" }) } },
        { body: { "id_token" => idp.id_token({ "exp" => Time.current.to_i - 3600 }) } },
        { body: { "id_token" => idp.id_token({}, key: :unknown) } }
      ].each_with_index do |answer, index|
        idp.answer_token_with(**answer)
        result = refresh(idp).call("rt-1", subject: "sub-1")
        assert_equal [ :unavailable, nil ], [ result.status, result.refresh_token ], "case #{index}"
      end
    end
  end

  # OpenID Connect Core 12.2: a refreshed ID token SHOULD carry no nonce,
  # and one that does carries the sign-in's, which the re-check does not
  # keep. The gem's `verify!(nonce: nil)` would refuse that token, so the
  # re-check does not compare the nonce at all.
  test "the refreshed ID token is verified with no nonce, whether it carries one or not" do
    with_fake_idp do |idp|
      [ {}, { "nonce" => "the-sign-in-nonce" } ].each do |claims|
        idp.answer_token_with(body: { "access_token" => "at", "id_token" => idp.id_token(claims) })
        assert_equal :ok, refresh(idp).call("rt-1", subject: "sub-1").status, claims.inspect
      end
      idp.answer_token_with(body: { "id_token" => idp.id_token({ "nonce" => "x", "sub" => "sub-2" }) })
      assert_equal :revoked, refresh(idp).call("rt-1", subject: "sub-1").status
    end
  end

  test "a blank refresh token is the caller's mistake and raises before anything is sent" do
    with_fake_idp do |idp|
      [ nil, "", 12 ].each { |token| assert_raises(ArgumentError) { refresh(idp).call(token, subject: "sub-1") } }
      assert_empty idp.requests
    end
  end

  test "the recheck span says the outcome, and no span, log line or inspect holds the tokens or the secret" do
    token = "planted-refresh-#{SecureRandom.hex(8)}"
    with_fake_idp(refresh_token: token) do |idp|
      rotated = "planted-rotated-#{SecureRandom.hex(8)}"
      idp.rotate_refresh_token(rotated)
      result = nil
      log = nil
      finished = spans do
        log = capture_log do
          result = refresh(idp).call(token, subject: "sub-1")
          idp.revoke!
          refresh(idp).call(rotated, subject: "sub-1")
        end
      end
      assert_equal [ :ok, rotated ], [ result.status, result.refresh_token ]

      rechecks = finished.select { |span| span.name == "auth.sso.recheck" }
      assert_equal [ :client, :client ], rechecks.map(&:kind)
      assert_equal [ "ok", "revoked" ], rechecks.map { |span| span.attributes["auth.outcome"] }
      assert rechecks.all? { |span| span.attributes["server.address"] == "127.0.0.1" }

      texts = finished.flat_map { |span| [ span.attributes.to_h.to_s, *Array(span.events).map { |event| "#{event.name} #{event.attributes}" } ] }
      texts += [ log, result.inspect, result.to_s, result.to_json, refresh(idp).inspect ]
      [ token, rotated, OidcHelper::CLIENT_SECRET, "planted" ].each { |secret| texts.each { |text| assert_not_includes text, secret } }
    end
  end
end
