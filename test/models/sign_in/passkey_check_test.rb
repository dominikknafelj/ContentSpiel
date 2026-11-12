require "test_helper"

class SignIn::PasskeyCheckTest < ActiveSupport::TestCase
  setup do
    @client = fake_authenticator
    @relying_party = passkey_relying_party(@client)
    @check = SignIn::PasskeyCheck.new(relying_party: @relying_party)
    @user = users(:reader)
    @passkey = add_passkey(@user, client: @client)
  end

  def assertion(challenge, user_handle: @user.webauthn_handle!, **extra)
    passkey_assertion(@client, challenge: challenge, user_handle: user_handle, **extra)
  end

  def verify(credential, challenge:, credentials: Passkey, ceremony: "sign_in")
    @check.verify(credential, challenge: challenge, credentials: credentials, ceremony: ceremony)
  end

  test "the options ask for user verification and allow the credentials given, or any" do
    json, challenge = @check.options

    assert_equal challenge, json[:challenge]
    assert_equal "required", json[:userVerification]
    assert_equal [], json[:allowCredentials]
    assert_equal @relying_party.id, json[:rpId]

    json, _challenge = @check.options(allow: [ @passkey.external_id ])
    assert_equal [ @passkey.external_id ], json[:allowCredentials].map { |descriptor| descriptor[:id] }
  end

  test "an assertion of a stored passkey verifies, moves its sign count and last_used_at, and one of another user's handle is refused" do
    _json, challenge = @check.options
    at = Time.zone.local(2026, 11, 12, 9, 0, 0)

    result = travel_to(at) { verify(assertion(challenge), challenge: challenge) }

    assert result.ok
    assert_equal @passkey, result.credential
    @passkey.reload
    assert_equal 1, @passkey.sign_count
    assert_equal at, @passkey.last_used_at

    _json, challenge = @check.options
    refused = verify(assertion(challenge, user_handle: users(:author).webauthn_handle!), challenge: challenge)
    assert_not refused.ok
    assert_nil refused.credential
    assert_equal 1, @passkey.reload.sign_count, "a refused assertion moves nothing"

    _json, challenge = @check.options
    assert_not verify(assertion(challenge, user_handle: nil), challenge: challenge).ok, "an assertion that names no handle is refused"
  end

  test "a sign count that went backwards, an unknown id, another challenge and a credential outside the relation are refused" do
    _json, challenge = @check.options
    assert verify(assertion(challenge), challenge: challenge).ok
    assert verify(assertion(challenge), challenge: challenge).ok, "a challenge is taken once by the caller, not here"

    _json, challenge = @check.options
    assert_not verify(assertion(challenge, sign_count: 1), challenge: challenge).ok, "a count that does not move forward"

    _json, other = @check.options
    assert_not verify(assertion(other), challenge: challenge).ok

    stranger = fake_authenticator
    stranger.create(challenge: challenge, rp_id: @relying_party.id, user_verified: true)
    assert_not verify(passkey_assertion(stranger, challenge: challenge, user_handle: @user.webauthn_handle!), challenge: challenge).ok, "an id that is stored nowhere"

    assert_not verify(assertion(challenge), challenge: challenge, credentials: users(:author).passkeys).ok, "another person's passkeys"
    assert verify(assertion(challenge), challenge: challenge, credentials: @user.passkeys).ok

    assert_raises(ArgumentError) { verify(assertion(challenge), challenge: challenge, ceremony: "elsewhere") }
  end

  test "an assertion without user verification is refused" do
    _json, challenge = @check.options
    unverified = @client.get(challenge: challenge, rp_id: @relying_party.id, user_verified: false,
      user_handle: WebAuthn.standard_encoder.decode(@user.webauthn_handle!)).to_json

    assert_not verify(unverified, challenge: challenge).ok
  end

  test "junk, an oversized credential and a hash of the wrong shape are refused without raising" do
    _json, challenge = @check.options
    valid = JSON.parse(assertion(challenge))
    response = valid["response"]

    junk = [
      "not json", "[]", "null", "",
      { "type" => "public-key" }.to_json,
      valid.merge("type" => "other").to_json,
      valid.merge("id" => 5).to_json,
      valid.merge("response" => nil).to_json,
      valid.merge("response" => response.merge("authenticatorData" => "AAAA")).to_json,
      valid.merge("response" => response.merge("signature" => "AAAA")).to_json,
      valid.merge("response" => response.merge("userHandle" => 5)).to_json,
      valid.merge("response" => response.merge("clientDataJSON" => Base64.urlsafe_encode64("5", padding: false))).to_json,
      nil, valid
    ]
    junk.each do |credential|
      assert_not verify(credential, challenge: challenge).ok, "refused: #{credential.inspect[0, 80]}"
    end

    parses = 0
    original = JSON.method(:parse)
    with_singleton_override(JSON, :parse, ->(*args, **kwargs) { parses += 1; original.call(*args, **kwargs) }) do
      assert_not verify(valid.merge("padding" => "a" * 20_000).to_json, challenge: challenge).ok
    end
    assert_equal 0, parses

    assert_equal 0, @passkey.reload.sign_count, "no junk moved the count"
    assert verify(valid.to_json, challenge: challenge).ok
  end

  test "each ceremony is one auth.passkey span with its ceremony and outcome, and no attribute holds the credential id or the challenge" do
    exporter = Rails.application.config.x.otel_test_exporter
    registration = SignIn::PasskeyRegistration.new(relying_party: @relying_party)
    planted = []

    exporter.reset
    Telemetry.tracer.in_span("probe", kind: :server) do
      _json, challenge = registration.options(user_handle: @user.webauthn_handle!, user_name: @user.email_address, display_name: @user.email_address)
      created = @client.create(challenge: challenge, rp_id: @relying_party.id, user_verified: true)
      result = registration.verify(created.to_json, challenge: challenge)
      planted += [ challenge, created["id"], created["response"]["clientDataJSON"], result.public_key ]
      registration.verify("not json", challenge: challenge)

      _json, challenge = @check.options
      credential = assertion(challenge)
      verify(credential, challenge: challenge, ceremony: "second_factor")
      verify(credential, challenge: "AAAA", ceremony: "confirm")
      planted += [ challenge, JSON.parse(credential)["response"]["clientDataJSON"], JSON.parse(credential)["response"]["signature"] ]
    end

    spans = exporter.finished_spans.select { |span| span.name == "auth.passkey" }
    assert_equal [ %w[register ok], %w[register refused], %w[second_factor ok], %w[confirm refused] ],
      spans.map { |span| [ span.attributes["auth.passkey.ceremony"], span.attributes["auth.outcome"] ] }

    planted += [ @passkey.external_id, @passkey.public_key, @user.email_address, @user.webauthn_handle! ]
    written = exporter.finished_spans.map do |span|
      [ span.name, span.attributes.to_a, span.status&.description, Array(span.events).map { |event| [ event.name, event.attributes.to_a ] } ].flatten.compact.join(" ")
    end.join("\n")
    planted.compact.each do |secret|
      assert_not_includes written, secret
      assert_not_includes written.downcase, secret.downcase
    end
  end
end
