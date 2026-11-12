module Admin
  # The second step of a sign-in to CS Studio: after a right password for an
  # account that holds a passkey or unused recovery codes
  # (`SessionsController`, `:second_factor_required`), one of the account's
  # own passkeys or one of its codes finishes the sign-in. On the product
  # layout, before any session exists, like sign-in itself.
  #
  # THE HELD ACCOUNT is SECOND_FACTOR_COOKIE, written by the password step
  # alone: `{ "user_id", "at" }`, encrypted, never the password. It stands
  # for SignIn::SECOND_STEP_LIFETIME from `at`, read here on every request
  # (`pending_user`), and is deleted on success, on Start over and once it
  # is late. No cookie (or one that does not open, which is none) is a
  # plain sign-in page; a late one, or one naming no account, is the
  # sign-in page with "That took too long. Sign in again."
  #
  # THE PROOF is `SignIn::Proof` under the `auth.second_factor` span, which
  # reserves in the account's bucket (or the known device's) before it
  # checks anything, the bucket the password step's count still stands in:
  # a wrong code or passkey counts as a wrong password does, the run closes
  # the account as wrong passwords do, and only the proof's success forgets
  # the run. So a stolen password earns no session, no known device and no
  # fresh guesses here. A wrong code and a used one are one sentence.
  #
  # THE ANSWERS. A code is a form: a refusal goes back to the code view
  # with its sentence; a success lands on Your account's passkeys, which
  # says how many codes are left (`flash[:recovery_code_left]`). A passkey
  # is the `passkey-sign-in` script's, answered 200 JSON `{ "location" }`
  # whatever happened, as the sign-in page's passkey is: CS Studio (or the
  # page the person was sent from) on success, this step again with its
  # sentence on a refusal. A closed bucket is "Try again in a few minutes."
  # (the address's: "Try again later."). The per-address rate limit counts
  # every POST of a proof, with sign-in's figures.
  #
  # WHAT IS AUDITED. A refused proof is `session.second_factor_failed`,
  # with no actor (nobody is signed in), the account as its subject and
  # `{ "method" }`; each bucket it closed is `session.locked`, and an
  # account's closure mails the account (`SignInLocks`). A success is
  # `session.created` with its method (`SignInCompletion`), and a code's is
  # also `recovery_code.used` `{ "left" }`, with the account's mail saying
  # a code was used. Never the code, the credential or the challenge.
  class SecondFactorsController < ApplicationController
    include MailLinkOrigin
    include PasskeyChallenges
    include SignInCompletion
    include SignInLocks

    layout "product"

    SECOND_FACTOR_COOKIE = :cs_second_factor

    allow_unauthenticated_access
    helper_method :passkey_relying_party

    before_action :require_passkey_relying_party, only: %i[ options passkey ]
    rate_limit to: 10, within: 3.minutes, only: %i[ code passkey ], store: SignIn.store,
      by: -> { VisitorAddress.key(request.remote_ip, purpose: SessionsController::RATE_LIMIT_PURPOSE) }, with: -> { answer_limited }
    # The options, as sign-in's are (`SessionsController`): a count of their own, a bare 429.
    rate_limit to: 30, within: 1.minute, only: :options, name: "options", store: SignIn.store,
      by: -> { VisitorAddress.key(request.remote_ip, purpose: SessionsController::RATE_LIMIT_PURPOSE) }, with: -> { head :too_many_requests }
    before_action :require_pending_user

    def show
      @user = pending_user
      @has_passkey = @user.passkeys.exists?
      @has_codes = @user.recovery_codes.unused.exists?
      @code_view = params[:with] == "code" || !@has_passkey
    end

    # The options for the account's own passkeys, and their challenge kept
    # for `passkey`.
    def options
      allow = pending_user.passkeys.pluck(:external_id)
      options, challenge = SignIn::PasskeyCheck.new(relying_party: passkey_relying_party).options(allow: allow)
      issue_passkey_challenge("second_factor", challenge)
      render json: options
    end

    # The challenge is taken before anything is decided, so a refused, a
    # locked or a late answer spends it too.
    def passkey
      user = pending_user
      challenge = take_passkey_challenge("second_factor")
      outcome = proof_for(user).passkey(params[:credential], challenge: challenge,
        check: SignIn::PasskeyCheck.new(relying_party: passkey_relying_party), ceremony: "second_factor")

      case outcome.status
      when :ok
        finish(user, method: "passkey")
        render json: { location: after_authentication_url }
      when :locked
        answer_passkey(locked_sentence(outcome))
      else
        refused(user, outcome, method: "passkey")
        answer_passkey(t(user.recovery_codes.unused.exists? ? "admin.second_factor.passkey_failed" : "admin.second_factor.passkey_failed_no_codes"))
      end
    end

    def code
      user = pending_user
      outcome = proof_for(user).recovery_code(params[:recovery_code])

      case outcome.status
      when :ok
        left = user.recovery_codes.unused.count
        finish(user, method: "recovery_code")
        Audit.record("recovery_code.used", subject: user, metadata: { "left" => left })
        SignInMailer.queue_alert(:recovery_code_used, user, used_at: Time.current, from_address: request.remote_ip, left: left, **mail_link_origin)
        flash[:recovery_code_left] = left
        redirect_to admin_account_path(anchor: "passkeys")
      when :locked
        redirect_to admin_second_factor_path(with: "code"), alert: locked_sentence(outcome)
      else
        refused(user, outcome, method: "recovery_code")
        redirect_to admin_second_factor_path(with: "code"), alert: t("admin.second_factor.code_failed")
      end
    end

    # Start over: the held account is forgotten, and the password is typed
    # again.
    def destroy
      cookies.delete(SECOND_FACTOR_COOKIE)
      redirect_to admin_sign_in_path, status: :see_other
    end

    private

    # The account the password step holds, while its cookie is no older than
    # SignIn::SECOND_STEP_LIFETIME, or nil.
    def pending_user
      return @pending_user if defined?(@pending_user)

      held = cookies.encrypted[SECOND_FACTOR_COOKIE]
      @pending_user =
        if held.is_a?(Hash) && held["at"].is_a?(Integer) && Time.zone.at(held["at"]) + SignIn::SECOND_STEP_LIFETIME >= Time.current
          User.find_by(id: held["user_id"])
        end
    end

    def require_pending_user
      return if pending_user

      opened = cookies.encrypted[SECOND_FACTOR_COOKIE].present?
      cookies.delete(SECOND_FACTOR_COOKIE)
      return head(:not_found) if action_name == "options"

      flash[:alert] = t("admin.sessions.second_factor_expired") if opened
      if action_name == "passkey"
        render json: { location: admin_sign_in_path }
      else
        redirect_to admin_sign_in_path
      end
    end

    def proof_for(user)
      SignIn::Proof.new(account: user, identifier: User.normalize_value_for(:email_address, user.email_address),
        address: request.remote_ip, device: known_device, span: "auth.second_factor")
    end

    def finish(user, method:)
      cookies.delete(SECOND_FACTOR_COOKIE)
      complete_sign_in(user, method: method)
    end

    def refused(user, outcome, method:)
      Audit.record("session.second_factor_failed", subject: user, metadata: { "method" => method })
      record_locks(outcome.trips, email: user.email_address, identifier: User.normalize_value_for(:email_address, user.email_address))
    end

    def locked_sentence(outcome)
      outcome.trips.any? { |trip| trip.bucket == :address_wide } ? t("admin.sessions.limited") : t("admin.sessions.locked")
    end

    def answer_passkey(sentence)
      flash[:alert] = sentence
      render json: { location: admin_second_factor_path }
    end

    # Past the per-address rate limit, inside the bucket's span, as sign-in
    # answers it.
    def answer_limited
      Telemetry.in_span("auth.throttle", attributes: { "auth.bucket" => "address", "auth.tripped" => true }) do
        if action_name == "passkey"
          answer_passkey(t("admin.sessions.limited"))
        else
          redirect_to admin_second_factor_path(with: "code"), alert: t("admin.sessions.limited")
        end
      end
    end

    def require_passkey_relying_party
      head :not_found if passkey_relying_party.nil?
    end
  end
end
