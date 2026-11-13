require "webauthn/fake_client"

# A passkey without a browser: the webauthn gem's own fake authenticator,
# which signs what a real one signs, so a test drives the same verification
# the app runs and nothing reaches the network.
#
# - `fake_authenticator(origin:)`: a client at `origin` (an integration
#   test's host unless named) holding its own authenticator, whose
#   credentials and counters live as long as the client does.
# - `passkey_registration(user, client:)`: the checked registration
#   (`SignIn::Passkeys::Registration::Result`) a service is handed, nothing
#   stored.
# - `add_passkey(user, client:, name:)`: a passkey registered through
#   `SignIn::Passkeys::Registration` and stored, as the app adds one.
# - `passkey_assertion(client, challenge:, user_handle:)`: the JSON a
#   browser sends for a sign-in, answered to `challenge` with user
#   verification; `user_handle` is the stored handle (`User#webauthn_id`),
#   which the response carries as the authenticator kept it.
#
# In a browser test, Chrome's own virtual authenticator (the DevTools
# protocol's `WebAuthn` domain), so the page's real `navigator.credentials`
# answers:
# - `with_virtual_authenticator { |authenticator| … }`: the app reached at
#   `localhost` (an IP has no relying party, so Capybara's 127.0.0.1 would
#   offer no passkey), and an authenticator that holds discoverable
#   credentials and verifies its user without a prompt; both are taken
#   back after the block, also when it fails. `on_localhost { … }` is the
#   address alone, for a page with no authenticator.
# - `add_virtual_passkey(user, authenticator)`: a P-256 key made here,
#   handed to the authenticator as a discoverable credential of `localhost`
#   for the user's handle, and stored as that user's passkey.
module PasskeyHelper
  PASSKEY_ORIGIN = "http://www.example.com".freeze
  PASSKEY_SITE_NAME = "ContentSpiel".freeze

  def fake_authenticator(origin: PASSKEY_ORIGIN)
    WebAuthn::FakeClient.new(origin, encoding: :base64url)
  end

  # The relying party a request from the client's origin meets.
  def passkey_relying_party(client)
    SignIn::Passkeys::RelyingParty.for(request_origin: client.origin, name: PASSKEY_SITE_NAME)
  end

  def passkey_registration(user, client: fake_authenticator)
    relying_party = passkey_relying_party(client)
    registration = SignIn::Passkeys::Registration.new(relying_party: relying_party)
    _options, challenge = registration.options(user_handle: user.webauthn_handle!, user_name: user.email_address, display_name: user.email_address)
    result = registration.verify(client.create(challenge: challenge, rp_id: relying_party.id, user_verified: true).to_json, challenge: challenge)
    raise "the fake authenticator's registration was refused" unless result.ok

    result
  end

  def add_passkey(user, client:, name: "1Password")
    result = passkey_registration(user, client: client)
    user.passkeys.create!(name: name, external_id: result.external_id, public_key: result.public_key,
      sign_count: result.sign_count, transports: result.transports)
  end

  def passkey_assertion(client, challenge:, user_handle: nil, rp_id: nil, sign_count: nil)
    raw_handle = user_handle && WebAuthn.standard_encoder.decode(user_handle)
    rp_id ||= passkey_relying_party(client)&.id
    client.get(challenge: challenge, rp_id: rp_id, user_verified: true, user_handle: raw_handle, sign_count: sign_count).to_json
  end

  def with_virtual_authenticator
    on_localhost do
      devtools = page.driver.browser.page
      devtools.command("WebAuthn.enable")
      authenticator = devtools.command("WebAuthn.addVirtualAuthenticator", options: {
        protocol: "ctap2", transport: "internal", hasResidentKey: true, hasUserVerification: true,
        isUserVerified: true, automaticPresenceSimulation: true
      }).fetch("authenticatorId")
      yield authenticator
    ensure
      if authenticator
        devtools.command("WebAuthn.removeVirtualAuthenticator", authenticatorId: authenticator)
        devtools.command("WebAuthn.disable")
      end
    end
  end

  # The app reached at `localhost`, where it has a relying party, for the
  # block.
  def on_localhost
    app_host = Capybara.app_host
    Capybara.app_host = "http://localhost:#{page.server.port}"
    yield
  ensure
    Capybara.app_host = app_host
  end

  def add_virtual_passkey(user, authenticator, name: "This browser")
    key = OpenSSL::PKey::EC.generate("prime256v1")
    credential_id = SecureRandom.random_bytes(16)
    handle = WebAuthn.standard_encoder.decode(user.webauthn_handle!)
    page.driver.browser.page.command("WebAuthn.addCredential", authenticatorId: authenticator, credential: {
      credentialId: Base64.strict_encode64(credential_id), isResidentCredential: true, rpId: "localhost",
      privateKey: Base64.strict_encode64(key.private_to_der), userHandle: Base64.strict_encode64(handle), signCount: 0
    })
    cose = COSE::Key::EC2.from_pkey(OpenSSL::PKey::EC.new(key.public_to_der))
    cose.alg = -7
    user.passkeys.create!(name: name, external_id: WebAuthn.standard_encoder.encode(credential_id),
      public_key: WebAuthn.standard_encoder.encode(cose.serialize), sign_count: 0)
  end
end
