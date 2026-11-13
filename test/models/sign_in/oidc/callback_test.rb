require "test_helper"

# The provider's answer to a sign-in: the code exchanged at the token
# endpoint, the ID token checked against the provider's keys and the kept
# nonce, and every refusal a reason word, never an exception, whatever the
# provider or the browser sent.
class SignIn::Oidc::CallbackTest < ActiveSupport::TestCase
  include LogCapture

  REDIRECT = "http://www.example.com/cs-studio/sign-in/sso/callback".freeze

  def kept(nonce: "nonce-#{SecureRandom.hex(8)}", state: "state-#{SecureRandom.hex(8)}", verifier: "verifier-#{SecureRandom.hex(16)}")
    { "state" => state, "nonce" => nonce, "verifier" => verifier, "at" => Time.current.to_i, "intent" => "sign_in", "invitation_id" => nil }
  end

  def callback(idp) = SignIn::Oidc::Callback.new(provider: idp.provider, redirect_uri: REDIRECT)

  # A code the fake provider answers once, bound to the kept nonce, the
  # verifier's challenge and the redirect URI, so a request missing any of
  # them is refused by the fake as a real provider would.
  def code(idp, kept)
    idp.code_for(nonce: kept["nonce"], challenge: SignIn::Oidc::Authorization.challenge(kept["verifier"]), redirect_uri: REDIRECT)
  end

  def token_posts(idp) = idp.requests.select { |request| request.path == "/idp/token" }
  def key_reads(idp) = idp.requests.count { |request| request.path == "/idp/keys" }

  # The exporter's spans for the block, run under a server span as a
  # request would run it (a CLIENT span with no recording parent is dropped).
  def spans(&block)
    exporter = Rails.application.config.x.otel_test_exporter
    exporter.reset
    Telemetry.tracer.in_span("probe", kind: :server, &block)
    exporter.finished_spans
  end

  # The token endpoint's answer for one exchange: the fake's own for
  # `kept`'s nonce, with `id_token` (and anything else) replaced.
  def answer_with_token(idp, id_token, **more)
    idp.answer_token_with(body: { "access_token" => "at", "token_type" => "Bearer", "id_token" => id_token }.merge(more).compact)
  end

  # An RS256 token for `claims` exactly as given, signed by the served key:
  # json-jwt turns `exp` and `iat` into integers, so a token whose claim is
  # of another type is written by hand.
  def hand_signed(idp, claims, header = {})
    segments = [ { "alg" => "RS256", "kid" => idp.key_id }.merge(header), claims ].map { |part| Base64.urlsafe_encode64(part.to_json, padding: false) }
    signature = OidcHelper::IDP_KEY.sign(OpenSSL::Digest.new("SHA256"), segments.join("."))
    [ *segments, Base64.urlsafe_encode64(signature, padding: false) ].join(".")
  end

  test "a code exchanged for a signed ID token answers its identity, with the refresh token when given" do
    with_fake_idp(email: "Reader@Example.com", name: "Rea Der") do |idp|
      kept = kept()
      result = callback(idp).call(params: { "code" => code(idp, kept), "state" => kept["state"] }, kept: kept)

      assert result.ok
      assert_nil result.reason
      identity = result.identity
      assert_equal [ idp.issuer, "sub-1", "Reader@Example.com", true, "Rea Der", "rt-1" ],
        [ identity.issuer, identity.subject, identity.email, identity.email_verified, identity.name, identity.refresh_token ]

      post = token_posts(idp).sole
      assert_equal({ "grant_type" => "authorization_code", "code" => post.params["code"], "redirect_uri" => REDIRECT,
        "code_verifier" => kept["verifier"] }, post.params)
      assert post.headers["authorization"].start_with?("Basic "), "client_secret_basic, the document's default"
    end

    with_fake_idp(offline_access: false) do |idp|
      kept = kept()
      result = callback(idp).call(params: { "code" => code(idp, kept), "state" => kept["state"] }, kept: kept)
      assert result.ok
      assert_nil result.identity.refresh_token
    end
  end

  test "action controller parameters are read as a hash is" do
    with_fake_idp do |idp|
      kept = kept()
      params = ActionController::Parameters.new("code" => code(idp, kept), "state" => kept["state"], "controller" => "x")
      assert callback(idp).call(params: params, kept: kept).ok
    end
  end

  test "client_secret_post is used when it is the only method listed, and basic otherwise" do
    with_fake_idp do |idp|
      idp.answer_discovery_with(body: idp.discovery_document.merge("token_endpoint_auth_methods_supported" => [ "client_secret_post" ]))
      kept = kept()
      assert callback(idp).call(params: { "code" => code(idp, kept), "state" => kept["state"] }, kept: kept).ok

      post = token_posts(idp).sole
      assert_nil post.headers["authorization"]
      assert_equal [ idp.client_id, OidcHelper::CLIENT_SECRET ], post.params.values_at("client_id", "client_secret")
    end

    with_fake_idp do |idp|
      idp.answer_discovery_with(body: idp.discovery_document.merge("token_endpoint_auth_methods_supported" => %w[client_secret_post client_secret_basic]))
      kept = kept()
      assert callback(idp).call(params: { "code" => code(idp, kept), "state" => kept["state"] }, kept: kept).ok
      assert token_posts(idp).sole.headers["authorization"].start_with?("Basic ")
      assert_nil token_posts(idp).sole.params["client_secret"]
    end
  end

  test "access_denied is cancelled and another error is provider_error" do
    with_fake_idp do |idp|
      kept = kept()
      { "access_denied" => "cancelled", "server_error" => "provider_error", "planted-error-text" => "provider_error" }.each do |error, reason|
        result = callback(idp).call(params: { "error" => error, "error_description" => "planted description", "state" => kept["state"] }, kept: kept)
        assert_not result.ok
        assert_nil result.identity
        assert_equal reason, result.reason, error
      end
      assert_equal "provider_error", callback(idp).call(params: { "error" => { "a" => "b" } }, kept: kept).reason
      assert_empty token_posts(idp)
    end
  end

  test "a state that does not match, no kept state and no code are bad_state, and nothing is sent to the provider" do
    with_fake_idp do |idp|
      kept = kept()
      code = code(idp, kept)
      [
        [ { "code" => code, "state" => "planted-other-state" }, kept ],
        [ { "code" => code, "state" => kept["state"].chop }, kept ],
        [ { "code" => code, "state" => "" }, kept ],
        [ { "code" => code }, kept ],
        [ { "code" => code, "state" => kept["state"] }, nil ],
        [ { "code" => code, "state" => kept["state"] }, {} ],
        [ { "code" => code, "state" => kept["state"] }, kept.merge("state" => nil) ],
        [ { "code" => code, "state" => kept["state"] }, kept.merge("nonce" => nil) ],
        [ { "code" => code, "state" => kept["state"] }, kept.merge("verifier" => "") ],
        [ { "code" => code, "state" => kept["state"] }, "planted-not-a-hash" ],
        [ { "state" => kept["state"] }, kept ],
        [ { "code" => "", "state" => kept["state"] }, kept ],
        [ { "code" => [ code ], "state" => kept["state"] }, kept ],
        [ { "code" => { "a" => code }, "state" => kept["state"] }, kept ],
        [ { "code" => code, "state" => [ kept["state"] ] }, kept ],
        [ { "code" => code, "state" => { "a" => kept["state"] } }, kept ],
        [ ActionController::Parameters.new("code" => code, "state" => { "a" => kept["state"] }), kept ],
        [ ActionController::Parameters.new("code" => code, "state" => [ kept["state"] ]), kept ]
      ].each_with_index do |(params, given), index|
        result = callback(idp).call(params: params, kept: given)
        assert_equal [ false, nil, "bad_state" ], [ result.ok, result.identity, result.reason ], "case #{index}"
      end
      assert_empty idp.requests, "neither discovery nor the token endpoint is asked"
    end
  end

  test "the token endpoint's refusal is provider_error, and a provider that is down, a 5xx or a body over the limit is unavailable" do
    with_fake_idp do |idp|
      kept = kept()
      params = { "code" => "planted-code-#{SecureRandom.hex(4)}", "state" => kept["state"] }
      assert_equal "provider_error", callback(idp).call(params: params, kept: kept).reason, "an unknown code is invalid_grant"

      idp.answer_token_with(status: 401, body: { "error" => "invalid_client", "error_description" => "planted" })
      assert_equal "provider_error", callback(idp).call(params: params, kept: kept).reason

      idp.answer_token_with(status: 500, body: "planted")
      assert_equal "unavailable", callback(idp).call(params: params, kept: kept).reason

      idp.answer_token_with(body: { "id_token" => "x" * SignIn::Oidc::MAX_BODY })
      assert_equal "unavailable", callback(idp).call(params: params, kept: kept).reason

      Rails.cache.clear
      idp.answer_discovery_with(status: 503, body: "down")
      assert_equal "unavailable", callback(idp).call(params: params, kept: kept).reason

      idp.down!
      Rails.cache.clear
      assert_equal "unavailable", callback(idp).call(params: params, kept: kept).reason
    end
  end

  # Review Focus 3: whatever the provider answers, the callback answers a
  # reason and never raises.
  test "alg none, wrong audience, wrong issuer, expired, unknown key and an oversized or non-JSON answer are refused without raising" do
    with_fake_idp do |idp|
      kept = kept()
      params = { "code" => "c", "state" => kept["state"] }
      now = Time.current.to_i
      refuse = lambda do |label, id_token = nil, body: nil, reason: "bad_token"|
        body ? idp.answer_token_with(body: body) : answer_with_token(idp, id_token)
        result = callback(idp).call(params: params, kept: kept)
        assert_equal [ false, nil, reason ], [ result.ok, result.identity, result.reason ], label
      end
      good = ->(claims = {}, **options) { idp.id_token({ "nonce" => kept["nonce"] }.merge(claims), **options) }

      # The fake's own token for the nonce verifies, so each refusal below is its one change.
      answer_with_token(idp, good.call)
      assert callback(idp).call(params: params, kept: kept).ok

      refuse.call("alg none", good.call(alg: "none"))
      header, payload, signature = good.call.split(".")
      none_header = Base64.urlsafe_encode64({ "alg" => "none", "kid" => idp.key_id }.to_json, padding: false)
      refuse.call("alg none with a kid and the signature kept", [ none_header, payload, signature ].join("."))
      refuse.call("alg none with a kid and no signature", "#{none_header}.#{payload}.")
      refuse.call("HS256 signed with the client secret", JSON::JWT.new(JSON.parse(Base64.urlsafe_decode64(payload)))
        .tap { |jwt| jwt.kid = idp.key_id }.sign(OidcHelper::CLIENT_SECRET, :HS256).to_s)
      refuse.call("RS256 with a tampered payload", [ header, Base64.urlsafe_encode64(JSON.parse(Base64.urlsafe_decode64(payload))
        .merge("sub" => "planted-sub").to_json, padding: false), signature ].join("."))

      refuse.call("wrong audience", good.call({ "aud" => "planted-other-client" }))
      refuse.call("no audience", good.call({ "aud" => nil }))
      refuse.call("an audience that is no string", good.call({ "aud" => { "a" => idp.client_id } }))
      refuse.call("several audiences with no azp", good.call({ "aud" => [ idp.client_id, "other" ] }))
      refuse.call("several audiences, azp another", good.call({ "aud" => [ idp.client_id, "other" ], "azp" => "other" }))
      refuse.call("one audience, azp another", good.call({ "azp" => "other" }))
      answer_with_token(idp, good.call({ "aud" => [ idp.client_id, "other" ], "azp" => idp.client_id }))
      assert callback(idp).call(params: params, kept: kept).ok, "several audiences with azp the client"

      refuse.call("wrong issuer", good.call({ "iss" => "https://planted.example.org" }))
      refuse.call("an issuer with a trailing slash", good.call({ "iss" => "#{idp.issuer}/" }))
      refuse.call("no issuer", good.call({ "iss" => nil }))
      refuse.call("no subject", good.call({ "sub" => nil }))
      refuse.call("a subject that is no string", good.call({ "sub" => 12 }))
      refuse.call("a subject over 255 characters", good.call({ "sub" => "s" * 256 }))

      refuse.call("expired", good.call({ "exp" => now - SignIn::Oidc::IdToken::LEEWAY.to_i - 1 }))
      refuse.call("no exp", good.call({ "exp" => nil }))
      claims = JSON.parse(Base64.urlsafe_decode64(payload))
      answer_with_token(idp, hand_signed(idp, claims))
      assert callback(idp).call(params: params, kept: kept).ok, "a hand-signed token of the fake's claims verifies"
      refuse.call("exp a string", hand_signed(idp, claims.merge("exp" => (now + 300).to_s)))
      refuse.call("iat a string", hand_signed(idp, claims.merge("iat" => now.to_s)))
      refuse.call("a crit header, signed", hand_signed(idp, claims, "crit" => [ "exp" ]))
      refuse.call("a jwk header naming its own key, signed by it", JSON::JWT.new(claims)
        .tap { |jwt| jwt.header.merge!(kid: idp.key_id, jwk: JSON::JWK.new(OidcHelper::UNKNOWN_KEY.public_key)) }.sign(OidcHelper::UNKNOWN_KEY, :RS256).to_s)
      answer_with_token(idp, good.call({ "exp" => now - 5 }))
      assert callback(idp).call(params: params, kept: kept).ok, "an exp a few seconds past is within the leeway"
      refuse.call("no iat", good.call({ "iat" => nil }))
      refuse.call("iat in the future", good.call({ "iat" => now + SignIn::Oidc::IdToken::LEEWAY.to_i + 5 }))

      refuse.call("another nonce", good.call({ "nonce" => "planted-other-nonce" }))
      refuse.call("no nonce", good.call({ "nonce" => nil }))
      refuse.call("a nonce that is no string", good.call({ "nonce" => [ kept["nonce"] ] }))

      reads = key_reads(idp)
      refuse.call("unknown key", good.call(key: :unknown))
      assert_equal reads + 1, key_reads(idp), "an unknown kid reads the keys once more, never more"
      no_kid = JSON::JWT.new(JSON.parse(Base64.urlsafe_decode64(payload))).sign(OidcHelper::IDP_KEY, :RS256).to_s
      refuse.call("no kid", no_kid)

      [ "", "planted.not.a-jwt", "a.b", "a.b.c.d.e", "%%%.%%%.%%%", "#{Base64.urlsafe_encode64("[1]")}.#{payload}.#{signature}",
        "#{header}.#{Base64.urlsafe_encode64('"planted"')}.#{signature}", "#{header}.#{Base64.urlsafe_encode64("{")}.#{signature}" ].each do |junk|
        refuse.call("junk #{junk.first(20)}", junk)
      end
      refuse.call("an id_token that is no string", { "a" => 1 })
      refuse.call("no id_token", body: { "access_token" => "at" })
      refuse.call("a body that is no object", body: "[1, 2]")
      refuse.call("a body that is no JSON", body: "<html>planted</html>")
      refuse.call("an oversized body", body: { "id_token" => good.call, "padding" => "x" * SignIn::Oidc::MAX_BODY }, reason: "unavailable")
    end
  end

  test "a key set out of reach is unavailable, and one lacking the token's kid is read again" do
    with_fake_idp do |idp|
      kept = kept()
      idp.provider.configuration
      idp.answer_keys_with(status: 503, body: "down")
      assert_equal "unavailable", callback(idp).call(params: { "code" => code(idp, kept), "state" => kept["state"] }, kept: kept).reason

      idp.answer_keys_with(body: { "keys" => [] })
      assert callback(idp).call(params: { "code" => code(idp, kept), "state" => kept["state"] }, kept: kept).ok
      assert_equal 3, key_reads(idp), "the refused read, the empty set and the read past it"
    end
  end

  test "a token signed by a rotated key is accepted after one more read of the keys" do
    with_fake_idp do |idp|
      kept = kept()
      idp.provider.keys
      assert_equal 1, key_reads(idp)

      idp.rotate_keys!
      assert callback(idp).call(params: { "code" => code(idp, kept), "state" => kept["state"] }, kept: kept).ok
      assert_equal 2, key_reads(idp)
    end
  end

  test "email_verified as the string true is not verified" do
    { "true" => false, 1 => false, nil => false, false => false, true => true }.each do |given, verified|
      with_fake_idp(email_verified: given) do |idp|
        kept = kept()
        identity = callback(idp).call(params: { "code" => code(idp, kept), "state" => kept["state"] }, kept: kept).identity
        assert_equal verified, identity.email_verified, given.inspect
      end
    end
  end

  test "an email that is no string, or over 254 characters, is no email, and a name that is no string is none" do
    [ [ "a" * 243 + "@example.com", nil ], [ { "a" => "b" }, nil ], [ "a" * 242 + "@example.com", "a" * 242 + "@example.com" ] ].each do |given, email|
      with_fake_idp(email: given, name: [ "planted" ]) do |idp|
        kept = kept()
        identity = callback(idp).call(params: { "code" => code(idp, kept), "state" => kept["state"] }, kept: kept).identity
        email.nil? ? assert_nil(identity.email) : assert_equal(email, identity.email)
        assert_nil identity.name
      end
    end
  end

  test "a refresh token that is no string is none" do
    with_fake_idp do |idp|
      kept = kept()
      answer_with_token(idp, idp.id_token({ "nonce" => kept["nonce"] }), "refresh_token" => { "a" => "b" })
      result = callback(idp).call(params: { "code" => "c", "state" => kept["state"] }, kept: kept)
      assert result.ok
      assert_nil result.identity.refresh_token
    end
  end

  test "the token span names the server and whether a refresh token came, and no span holds the code, the tokens or the secret" do
    with_fake_idp(refresh_token: "planted-refresh-#{SecureRandom.hex(8)}") do |idp|
      kept = kept(nonce: "planted-nonce-#{SecureRandom.hex(8)}", state: "planted-state-#{SecureRandom.hex(8)}",
        verifier: "planted-verifier-#{SecureRandom.hex(16)}")
      code = code(idp, kept)
      result = nil
      log = nil
      finished = spans { log = capture_log { result = callback(idp).call(params: { "code" => code, "state" => kept["state"] }, kept: kept) } }
      assert result.ok

      token = finished.select { |span| span.name == "auth.sso.token" }.sole
      assert_equal :client, token.kind
      assert_equal({ "server.address" => "127.0.0.1", "auth.sso.refresh_token" => true }, token.attributes.to_h)

      secrets = [ code, kept["state"], kept["nonce"], kept["verifier"], OidcHelper::CLIENT_SECRET, result.identity.refresh_token ]
      texts = finished.flat_map { |span| [ span.name, span.attributes.to_h.to_s, *Array(span.events).map { |event| "#{event.name} #{event.attributes}" } ] }
      texts += [ log, result.inspect, result.to_s, result.identity.inspect, callback(idp).inspect ]
      secrets.each { |secret| texts.each { |text| assert_not_includes text, secret } }
      assert texts.none? { |text| text.include?("planted") }, "no planted value, nor the ID token's claims, is anywhere"

      finished = spans do
        log = capture_log do
          idp.answer_token_with(status: 400, body: { "error" => "invalid_grant", "error_description" => "planted description #{code}" })
          assert_equal "provider_error", callback(idp).call(params: { "code" => code, "state" => kept["state"] }, kept: kept).reason
          idp.answer_token_with(body: "<html>planted #{code}</html>")
          assert_equal "bad_token", callback(idp).call(params: { "code" => code, "state" => kept["state"] }, kept: kept).reason
        end
      end
      tokens = finished.select { |span| span.name == "auth.sso.token" }
      assert_equal [ "400", nil ], tokens.map { |span| span.attributes["error.type"] }
      assert_equal [ 400, nil ], tokens.map { |span| span.attributes["http.response.status_code"] }
      texts = finished.flat_map { |span| [ span.attributes.to_h.to_s, *Array(span.events).map { |event| "#{event.name} #{event.attributes}" } ] } + [ log ]
      assert texts.none? { |text| text.include?("planted") || text.include?(code) }
    end
  end

  test "an unreachable token endpoint's span names the error's class" do
    with_fake_idp do |idp|
      kept = kept()
      idp.provider.configuration
      idp.down!
      finished = spans { assert_equal "unavailable", callback(idp).call(params: { "code" => "c", "state" => kept["state"] }, kept: kept).reason }
      assert_equal "Errno::ECONNREFUSED", finished.select { |span| span.name == "auth.sso.token" }.sole.attributes["error.type"]
    end
  end
end
