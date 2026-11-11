require "webauthn/fake_client"

# A passkey without a browser: the webauthn gem's own fake authenticator,
# which signs what a real one signs, so a test drives the same verification
# the app runs and nothing reaches the network.
#
# - `fake_authenticator(origin:)`: a client at `origin` (an integration
#   test's host unless named) holding its own authenticator, whose
#   credentials and counters live as long as the client does.
# - `add_passkey(user, client:, name:)`: a passkey registered through
#   `SignIn::PasskeyRegistration` and stored, as the app adds one.
# - `passkey_assertion(client, challenge:, user_handle:)`: the JSON a
#   browser sends for a sign-in, answered to `challenge` with user
#   verification; `user_handle` is the stored handle (`User#webauthn_id`),
#   which the response carries as the authenticator kept it.
module PasskeyHelper
  PASSKEY_ORIGIN = "http://www.example.com".freeze
  PASSKEY_SITE_NAME = "ContentSpiel".freeze

  def fake_authenticator(origin: PASSKEY_ORIGIN)
    WebAuthn::FakeClient.new(origin, encoding: :base64url)
  end

  # The relying party a request from the client's origin meets.
  def passkey_relying_party(client)
    SignIn::RelyingParty.for(address: SiteAddress.current, request_origin: client.origin, name: PASSKEY_SITE_NAME)
  end

  def add_passkey(user, client:, name: "1Password")
    relying_party = passkey_relying_party(client)
    registration = SignIn::PasskeyRegistration.new(relying_party: relying_party)
    _options, challenge = registration.options(user_handle: user.webauthn_handle!, user_name: user.email_address, display_name: user.email_address)
    result = registration.verify(client.create(challenge: challenge, rp_id: relying_party.id, user_verified: true).to_json, challenge: challenge)
    raise "the fake authenticator's registration was refused" unless result.ok

    user.passkeys.create!(name: name, external_id: result.external_id, public_key: result.public_key,
      sign_count: result.sign_count, transports: result.transports)
  end

  def passkey_assertion(client, challenge:, user_handle: nil, rp_id: nil, sign_count: nil)
    raw_handle = user_handle && WebAuthn.standard_encoder.decode(user_handle)
    rp_id ||= passkey_relying_party(client)&.id
    client.get(challenge: challenge, rp_id: rp_id, user_verified: true, user_handle: raw_handle, sign_count: sign_count).to_json
  end
end
