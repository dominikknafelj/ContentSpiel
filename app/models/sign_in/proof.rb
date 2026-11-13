module SignIn
  # A second proof of an account the caller already holds: a recovery code
  # or a passkey for the second step of a sign-in, a passkey or the
  # password again for Confirm it's you. Each is decided as a password
  # attempt is (`PasswordAttempt`), counted in the account's bucket, or the
  # known device's, BEFORE anything is checked (`Throttle`, "A SECOND
  # PROOF"), and answered as a `SignIn::Outcome`:
  #
  # - a closed bucket is `:locked` with its trip, and nothing is checked
  #   (no code is used, no passkey verified, no password hashed);
  # - a right proof forgets the bucket's run (`Throttle#record_success`),
  #   the one the password step began included, and is `:ok`;
  # - a wrong one is `:refused` with the buckets its reservation closed;
  # - a right one for an account the caller's rule refuses (`allowed:`,
  #   `SignInRules.passkey_allowed?`: a linked account, a non-owner under
  #   SSO_REQUIRED) is a wrong one: checked first, as any proof is (the
  #   passkey verified, the code used), then `:refused` with the count its
  #   reservation made left standing and the run not forgotten. So a second
  #   step held from before the rule applied (SSO_REQUIRED switched on, or
  #   the account linked, while the step was held) signs nobody in, and
  #   neither the answer, the bucket nor the span tells the rule from a
  #   wrong proof.
  #
  # A wrong code, a used one and anything that is no code are one refusal,
  # which says nothing of which it was. A passkey is looked for among the
  # account's own (`account.passkeys`), never every account's. It knows no
  # session, cookie, route or mail: the caller signs in or confirms,
  # audits, mails and answers.
  #
  # Each call is one span named by the caller's step (SPANS), with
  # `auth.method` and `auth.outcome`; the code, the password and the
  # credential reach no span.
  class Proof
    SPANS = %w[auth.second_factor auth.confirmation].freeze

    # `identifier`: the account bucket's key, the email as the accounts
    # store it. `device`: the `KnownDevice` the browser carries, or nil.
    # `allowed`: whether the account may be let in by a right proof.
    def initialize(account:, identifier:, address:, span:, device: nil, throttle: SignIn::Throttle.new, allowed: ->(_account) { true })
      raise ArgumentError, "#{span.inspect} is not among #{SPANS}" unless SPANS.include?(span)

      @allowed = allowed
      @account = account
      @identifier = identifier
      @address = address
      @device = device
      @span = span
      @throttle = throttle
    end

    # Uses one of the account's unused codes, once (`RecoveryCode::Redeem`).
    def recovery_code(text)
      prove("recovery_code") do
        Telemetry.in_span("auth.recovery_code") do |span|
          @account.recovery_codes.redeem(text).tap { |used| Telemetry.record(span, "auth.outcome" => used ? "ok" : "refused") }
        end
      end
    end

    # The account's password, a list or a hash as "".
    def password(text)
      prove("password") { @account.authenticate(text.is_a?(String) ? text : "") ? true : false }
    end

    # An assertion of one of the account's passkeys, over the challenge the
    # caller kept (`PasskeyCheck#verify`, which records the use).
    def passkey(credential_json, challenge:, check:, ceremony:)
      prove("passkey") { check.verify(credential_json, challenge: challenge, credentials: @account.passkeys, ceremony: ceremony).ok }
    end

    private

    def prove(method)
      Telemetry.in_span(@span, attributes: { "auth.method" => method }) do |span|
        decide { yield }.tap { |outcome| Telemetry.record(span, "auth.outcome" => outcome.status.to_s) }
      end
    end

    def decide
      reservation = @throttle.reserve(identifier: @identifier, address: @address, device: known_device_id)
      return outcome(:locked, trips: [ reservation.refused_by ]) unless reservation.ok?
      return outcome(:refused, trips: reservation.closes) unless yield && @allowed.call(@account)

      @throttle.record_success(identifier: @identifier, address: @address, device: known_device_id)
      outcome(:ok, account: @account)
    end

    # The device's id when it has signed in to this account before.
    def known_device_id
      @device.id if @device&.knows?(@identifier)
    end

    # No bot check stands before a second proof: the password step met it.
    def outcome(status, account: nil, trips: [])
      Outcome.new(status: status, account: account, trips: trips, bot_check_due: false)
    end
  end
end
