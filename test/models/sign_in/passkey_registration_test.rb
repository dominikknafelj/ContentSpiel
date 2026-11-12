require "test_helper"

class SignIn::PasskeyRegistrationTest < ActiveSupport::TestCase
  setup do
    @client = fake_authenticator
    @relying_party = passkey_relying_party(@client)
    @registration = SignIn::PasskeyRegistration.new(relying_party: @relying_party)
    @user = users(:reader)
  end

  def options(**extra)
    @registration.options(user_handle: @user.webauthn_handle!, user_name: @user.email_address, display_name: @user.email_address, **extra)
  end

  def created(challenge, **extra)
    @client.create(challenge: challenge, rp_id: @relying_party.id, user_verified: true, **extra).to_json
  end

  test "the options ask for a discoverable credential with user verification, no attestation, and exclude the ones given" do
    json, challenge = options(exclude: [ "abc" ])

    assert_equal challenge, json[:challenge]
    assert_equal({ residentKey: "required", requireResidentKey: true, userVerification: "required" }, json[:authenticatorSelection].symbolize_keys)
    assert_equal "none", json[:attestation]
    assert_equal [ "abc" ], json[:excludeCredentials].map { |descriptor| descriptor[:id] }
    assert_equal @user.webauthn_handle!, json[:user][:id]
    assert_equal @relying_party.id, json[:rp][:id]
    assert_not_equal challenge, options.last, "every call has a challenge of its own"
  end

  test "a registration made by an authenticator verifies, and one answered to another challenge does not" do
    _json, challenge = options
    result = @registration.verify(created(challenge), challenge: challenge)

    assert result.ok
    assert result.external_id.present?
    assert result.public_key.present?
    assert_equal 0, result.sign_count
    assert_equal [ "internal" ], result.transports

    _json, other = options
    refused = @registration.verify(created(other), challenge: challenge)
    assert_not refused.ok
    assert_nil refused.external_id
    assert_nil refused.public_key
  end

  test "a registration without user verification, or answered for another site, is refused" do
    _json, challenge = options

    assert_not @registration.verify(created(challenge, user_verified: false), challenge: challenge).ok
    elsewhere = fake_authenticator(origin: "http://evil.example.net")
    assert_not @registration.verify(elsewhere.create(challenge: challenge, user_verified: true).to_json, challenge: challenge).ok
    assert_not @registration.verify(created(challenge), challenge: nil).ok, "no challenge is no registration"
  end

  test "junk, an oversized credential and a hash of the wrong shape are refused without raising" do
    _json, challenge = options
    valid = JSON.parse(created(challenge))

    junk = [
      "not json", "[]", "null", "42", "",
      { "type" => "public-key" }.to_json,
      valid.merge("type" => "other").to_json,
      valid.merge("id" => "AAAA").to_json,
      valid.merge("rawId" => 5).to_json,
      valid.merge("response" => "x").to_json,
      valid.merge("response" => [ 1 ]).to_json,
      valid.merge("response" => valid["response"].merge("attestationObject" => "AAAAAAAA")).to_json,
      valid.merge("response" => valid["response"].merge("attestationObject" => "!!!")).to_json,
      valid.merge("response" => valid["response"].merge("clientDataJSON" => Base64.urlsafe_encode64("[]", padding: false))).to_json,
      valid.merge("response" => valid["response"].merge("clientDataJSON" => Base64.urlsafe_encode64("{}", padding: false))).to_json,
      valid.merge("response" => valid["response"].merge("transports" => "usb")).to_json,
      nil, 42, valid
    ]
    junk.each do |credential|
      result = @registration.verify(credential, challenge: challenge)
      assert_not result.ok, "refused: #{credential.inspect[0, 80]}"
    end

    oversized = { "type" => "public-key", "padding" => "a" * 20_000 }.to_json
    assert_operator oversized.bytesize, :>, SignIn::PasskeyRegistration::MAX_CREDENTIAL_BYTES
    parses = 0
    original = JSON.method(:parse)
    with_singleton_override(JSON, :parse, ->(*args, **kwargs) { parses += 1; original.call(*args, **kwargs) }) do
      assert_not @registration.verify(oversized, challenge: challenge).ok
    end
    assert_equal 0, parses, "an oversized credential is never parsed"

    assert @registration.verify(valid.to_json, challenge: challenge).ok, "and the valid one still verifies"
  end
end
