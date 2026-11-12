module Admin
  # Confirm it's you: the signed-in person proves it again, with their
  # password or one of their own passkeys, before a change to how they sign
  # in (`Admin::RecentConfirmation`, which gates the change). A right proof
  # confirms THIS session (`Session#confirm!`) for Session::CONFIRM_WINDOW,
  # and nothing else of the person's.
  #
  # THE PROOF is `SignIn::Proof` under the `auth.confirmation` span, which
  # reserves in the account's bucket (or the known device's) before it
  # checks anything: a wrong password here counts as a wrong one at sign-in,
  # the run closes the account as wrong passwords do, and a closed bucket
  # checks nothing. So a session left open on someone else's screen buys no
  # more guesses at the password than the sign-in page gives. A passkey is
  # looked for among the person's own alone (`Current.user.passkeys`), and
  # its user handle must be the stored one (`SignIn::PasskeyCheck`).
  #
  # THE ANSWERS are JSON for `admin--passkeys--confirm`, the error a
  # sentence the dialog shows as it is:
  #
  #   a right proof                          200 { "confirmed": true }
  #   a wrong password                       422 { "error": wrong_password }
  #   a wrong passkey (or challenge)         422 { "error": passkey_failed }
  #   a closed bucket, or the refusal that   429 { "error": limited }
  #   closed one, or the rate limit
  #
  # `options` hands out the request options for the person's passkeys,
  # with a challenge of the purpose "confirm" kept for `passkey`; 404 for a
  # person with none, or at an IP address (no relying party).
  #
  # WHAT IS AUDITED. A checked proof that failed is
  # `session.confirmation_failed`, the person as its actor and its subject,
  # with `{ "method" }`; each bucket it closed is `session.locked`, and the
  # account's closure mails the account (`SignInLocks`), as at sign-in. A
  # right proof records nothing, and neither does an attempt a lock refused
  # (nothing was checked). Never the password, the credential or the
  # challenge.
  class ConfirmationsController < BaseController
    include MailLinkOrigin
    include PasskeyChallenges
    include SignInLocks

    RATE_LIMIT_PURPOSE = "content_spiel confirmation rate limit".freeze
    WORDS = "admin.components.ui.confirm_identity_dialog".freeze

    before_action :require_passkey_relying_party, only: %i[ options passkey ]
    # Every POST of a proof, a success and a refusal alike, per address and
    # in the throttle's store, as sign-in's limit counts (`SessionsController`).
    rate_limit to: 10, within: 3.minutes, only: %i[ create passkey ], store: SignIn.store,
      by: -> { VisitorAddress.key(request.remote_ip, purpose: RATE_LIMIT_PURPOSE) }, with: -> { answer_limited }

    def create
      answer(proof.password(params[:password]), method: "password", failed: :wrong_password)
    end

    def options
      allow = Current.user.passkeys.pluck(:external_id)
      return head(:not_found) if allow.empty?

      options, challenge = SignIn::PasskeyCheck.new(relying_party: passkey_relying_party).options(allow: allow)
      issue_passkey_challenge("confirm", challenge)
      render json: options
    end

    # The challenge is taken before anything is decided, so a refused or a
    # locked answer spends it too.
    def passkey
      challenge = take_passkey_challenge("confirm")
      outcome = proof.passkey(params[:credential], challenge: challenge,
        check: SignIn::PasskeyCheck.new(relying_party: passkey_relying_party), ceremony: "confirm")
      answer(outcome, method: "passkey", failed: :passkey_failed)
    end

    private

    def identifier = User.normalize_value_for(:email_address, Current.user.email_address)

    def proof
      SignIn::Proof.new(account: Current.user, identifier: identifier, address: request.remote_ip,
        device: SignIn::KnownDevice.read(cookies.encrypted[SignInCompletion::DEVICE_COOKIE]), span: "auth.confirmation")
    end

    def answer(outcome, method:, failed:)
      case outcome.status
      when :ok
        Current.session.confirm!
        render json: { confirmed: true }
      when :locked
        answer_limited
      else
        Audit.record("session.confirmation_failed", subject: Current.user, metadata: { "method" => method })
        record_locks(outcome.trips, email: Current.user.email_address, identifier: identifier)
        outcome.trips.any? ? answer_limited : render(json: { error: t("#{WORDS}.#{failed}") }, status: :unprocessable_entity)
      end
    end

    def answer_limited
      render json: { error: t("#{WORDS}.limited") }, status: :too_many_requests
    end

    def require_passkey_relying_party
      head :not_found if passkey_relying_party.nil?
    end
  end
end
