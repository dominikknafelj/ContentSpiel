module SignIn
  # Registering a passkey: the options a browser's `navigator.credentials.
  # create` is handed, and the check of what it answers. The caller keeps
  # the challenge (one use, five minutes, one purpose) and stores the
  # result; nothing here writes a record.
  #
  # What is asked for: a discoverable credential (so a sign-in needs no
  # email first), user verification (the device's PIN or biometric, so a
  # passkey is a factor of its own), and no attestation (which authenticator
  # it is is none of the site's business). `exclude` is the person's
  # credentials, so an authenticator that already holds one says so instead
  # of making a second.
  #
  # Each verification is one `auth.passkey` span, `ceremony: "register"`,
  # whose attributes are the ceremony and the outcome: never the challenge,
  # the credential id, the key or the client data.
  class PasskeyRegistration
    MAX_CREDENTIAL_BYTES = PasskeyCredential::MAX_CREDENTIAL_BYTES

    AUTHENTICATOR_SELECTION = { resident_key: "required", require_resident_key: true, user_verification: "required" }.freeze

    # `external_id` and `public_key` base64url, as `Passkey` stores them.
    Result = Data.define(:ok, :external_id, :public_key, :sign_count, :transports)
    REFUSED = Result.new(ok: false, external_id: nil, public_key: nil, sign_count: nil, transports: []).freeze

    def initialize(relying_party:)
      @relying_party = relying_party
    end

    # The options as JSON for the browser, and their challenge for the
    # caller to keep. `user_handle` is the account's `webauthn_handle!`,
    # never the email, which is only the name the browser shows.
    def options(user_handle:, user_name:, display_name:, exclude: [])
      options = @relying_party.options_for_registration(
        user: { id: user_handle, name: user_name, display_name: display_name },
        authenticator_selection: AUTHENTICATOR_SELECTION.dup,
        attestation: "none",
        exclude: exclude
      )
      [ options.as_json, options.challenge ]
    end

    def verify(credential_json, challenge:)
      Telemetry.in_span("auth.passkey", attributes: { "auth.passkey.ceremony" => "register" }) do |span|
        result = check(credential_json, challenge)
        Telemetry.record(span, "auth.outcome" => result.ok ? "ok" : "refused")
        result
      end
    end

    private

    def check(credential_json, challenge)
      return REFUSED unless challenge.is_a?(String)

      hash = PasskeyCredential.parse(credential_json, fields: %w[attestationObject])
      return REFUSED if hash.nil?

      credential = WebAuthn::Credential.from_create(hash, relying_party: @relying_party)
      credential.verify(challenge, user_verification: true)
      Result.new(ok: true, external_id: credential.id, public_key: credential.public_key,
        sign_count: credential.sign_count, transports: Array(credential.response.transports))
    rescue *PasskeyCredential::MALFORMED
      REFUSED
    end
  end
end
