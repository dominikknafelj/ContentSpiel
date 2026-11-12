module SignIn
  # Checking a passkey: the options a browser's `navigator.credentials.get`
  # is handed, and the check of the assertion it answers, for every
  # ceremony that asks for one (CEREMONIES). The caller keeps the challenge
  # (one use, five minutes, one purpose) and decides what a success opens.
  #
  # An assertion passes only when
  # - its credential id is one of `credentials` (all passkeys for a sign-in
  #   that named nobody, the person's own for a second step or a
  #   confirmation),
  # - its signature verifies under that credential's stored key, over the
  #   challenge, the origin and the relying party's id,
  # - the device verified its user (PIN or biometric),
  # - the authenticator's counter moved forward, or stayed 0 on both sides
  #   (a synced passkey keeps 0): a count that went backwards is a cloned
  #   authenticator, and is refused,
  # - and the handle it names is the credential's account's, so a passkey
  #   cannot speak for another account.
  #
  # A success records the use (`Passkey#used!`). Each verification is one
  # `auth.passkey` span with the ceremony and the outcome, never the
  # challenge, the credential id or the client data.
  class PasskeyCheck
    CEREMONIES = %w[sign_in second_factor confirm].freeze

    Result = Data.define(:ok, :credential)
    REFUSED = Result.new(ok: false, credential: nil).freeze

    def initialize(relying_party:)
      @relying_party = relying_party
    end

    # The options as JSON for the browser, and their challenge for the
    # caller to keep. `allow` is credential ids; empty lets the browser
    # offer any passkey of the site.
    def options(allow: [])
      options = @relying_party.options_for_authentication(allow: allow, user_verification: "required")
      [ options.as_json, options.challenge ]
    end

    # `credentials` answers `find_by(external_id:)`: `Passkey`, or a
    # person's `passkeys`.
    def verify(credential_json, challenge:, credentials:, ceremony:)
      raise ArgumentError, "#{ceremony.inspect} is not among #{CEREMONIES}" unless CEREMONIES.include?(ceremony)

      Telemetry.in_span("auth.passkey", attributes: { "auth.passkey.ceremony" => ceremony }) do |span|
        result = check(credential_json, challenge, credentials)
        Telemetry.record(span, "auth.outcome" => result.ok ? "ok" : "refused")
        result
      end
    end

    private

    def check(credential_json, challenge, credentials)
      return REFUSED unless challenge.is_a?(String)

      hash = PasskeyCredential.parse(credential_json, fields: %w[authenticatorData signature])
      return REFUSED if hash.nil?

      passkey = credentials.find_by(external_id: hash["id"])
      return REFUSED if passkey.nil?

      assertion = WebAuthn::Credential.from_get(hash, relying_party: @relying_party)
      assertion.verify(challenge, public_key: passkey.public_key, sign_count: passkey.sign_count, user_verification: true)
      return REFUSED unless same_handle?(assertion.user_handle, passkey.user_handle)

      passkey.used!(sign_count: assertion.sign_count)
      Result.new(ok: true, credential: passkey)
    rescue *PasskeyCredential::MALFORMED
      REFUSED
    end

    def same_handle?(given, stored)
      given.is_a?(String) && stored.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(given, stored)
    end
  end
end
