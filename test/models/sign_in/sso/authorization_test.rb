require "test_helper"

# The request that sends a person to the provider: a fresh state, nonce and
# PKCE verifier each time, the URL built by the openid_connect gem, and
# nothing of the three in what the object says of itself.
class SignIn::Sso::AuthorizationTest < ActiveSupport::TestCase
  REDIRECT = "http://www.example.com/cs-studio/sign-in/sso/callback".freeze

  def query(url) = Rack::Utils.parse_query(URI(url).query)

  def challenge(verifier) = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

  test "the authorization URL carries the state, the nonce, an S256 challenge and the redirect URI, and asks offline_access only when listed" do
    with_fake_idp do |idp|
      authorization = SignIn::Sso::Authorization.start(provider: idp.provider, redirect_uri: REDIRECT)
      assert authorization.url.start_with?("#{idp.issuer}/authorize?")

      params = query(authorization.url)
      assert_equal({
        "client_id" => idp.client_id, "redirect_uri" => REDIRECT, "response_type" => "code",
        "scope" => "openid email profile offline_access",
        "state" => authorization.state, "nonce" => authorization.nonce,
        "code_challenge" => challenge(authorization.verifier), "code_challenge_method" => "S256"
      }, params)

      [ authorization.state, authorization.nonce, authorization.verifier ].each do |value|
        assert_match(/\A[A-Za-z0-9_-]{43}\z/, value)
      end
      assert_equal 3, [ authorization.state, authorization.nonce, authorization.verifier ].uniq.size
      assert_not_includes authorization.url, authorization.verifier

      again = SignIn::Sso::Authorization.start(provider: idp.provider, redirect_uri: REDIRECT)
      assert_empty [ again.state, again.nonce, again.verifier ] & [ authorization.state, authorization.nonce, authorization.verifier ]
    end

    with_fake_idp(offline_access: false) do |idp|
      authorization = SignIn::Sso::Authorization.start(provider: idp.provider, redirect_uri: REDIRECT)
      assert_equal "openid email profile", query(authorization.url)["scope"]
    end
  end

  test "a provider that cannot be reached raises Unavailable from start" do
    with_fake_idp do |idp|
      idp.down!
      error = assert_raises(SignIn::Sso::Unavailable) { SignIn::Sso::Authorization.start(provider: idp.provider, redirect_uri: REDIRECT) }
      assert_equal "unreachable", error.reason
    end
  end

  test "inspect, to_s and as_json hold no state, nonce or verifier" do
    with_fake_idp do |idp|
      authorization = SignIn::Sso::Authorization.start(provider: idp.provider, redirect_uri: REDIRECT)
      [ authorization.inspect, authorization.to_s, "#{authorization}", authorization.to_json, { a: authorization }.to_json ].each do |text|
        [ authorization.state, authorization.nonce, authorization.verifier ].each { |secret| assert_not_includes text, secret }
      end
      assert_includes authorization.inspect, "127.0.0.1"
    end
  end

  test "an identity's inspect and as_json hold no refresh token or email" do
    identity = SignIn::Sso::Identity.new(issuer: "https://idp.example.org", subject: "sub-1", email: "planted@example.org",
      email_verified: true, name: "Rea Der", refresh_token: "planted-refresh-token")
    [ identity.inspect, identity.to_s, identity.to_json, { a: identity }.to_json ].each do |text|
      assert_not_includes text, "planted"
      assert_includes text, "sub-1"
    end
    assert_equal "planted-refresh-token", identity.refresh_token
  end

  # The fake provider is what the code exchange's tests and the browser tests
  # follow: its authorization endpoint sends the person back to the redirect
  # URI with a code and the state, and its token endpoint answers that code
  # with an ID token for the authorization's nonce, once, for the verifier
  # alone.
  test "the fake provider redirects back with a code bound to the nonce, or access_denied after deny!" do
    with_fake_idp do |idp|
      authorization = SignIn::Sso::Authorization.start(provider: idp.provider, redirect_uri: REDIRECT)
      back = idp.authorize(authorization.url)
      assert back.start_with?("#{REDIRECT}?")
      params = query(back)
      assert_equal authorization.state, params["state"]

      exchange = ->(verifier) { idp.post_token("grant_type" => "authorization_code", "code" => params["code"], "redirect_uri" => REDIRECT, "code_verifier" => verifier) }
      assert_equal [ 400, "invalid_grant" ], exchange.call("planted-wrong-verifier").then { |status, body| [ status, body["error"] ] }
      status, body = exchange.call(authorization.verifier)
      assert_equal 200, status
      assert_equal "rt-1", body["refresh_token"]
      claims = JSON::JWT.decode(body["id_token"], idp.public_key)
      assert_equal [ authorization.nonce, "sub-1", "reader@example.com", idp.client_id, idp.issuer ],
        claims.values_at("nonce", "sub", "email", "aud", "iss")
      assert_equal 400, exchange.call(authorization.verifier).first, "a code is answered once"

      idp.deny!
      params = query(idp.authorize(SignIn::Sso::Authorization.start(provider: idp.provider, redirect_uri: REDIRECT).url))
      assert_equal "access_denied", params["error"]
      assert_nil params["code"]
    end
  end
end
