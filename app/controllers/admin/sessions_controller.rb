module Admin
  # CS Studio's sign-in. Namespaced and routed under
  # ContentSpiel::ADMIN_PATH like every other admin controller, but not a
  # subclass of Admin::BaseController: that base sets `layout "admin"` and
  # `Current.channel = :admin` for signed-in screens, while sign-in itself
  # must render *before* a session exists, in the shared product layout the
  # setup wizard also uses.
  #
  # The decision is `SignIn::PasswordAttempt`'s (the bot check, the account
  # and wide address buckets, the password); this controller answers it,
  # signs the account in, and audits.
  #
  # THE ANSWERS. Every refusal is the same redirect to the sign-in page with
  # one alert (`refusal_sentence`), and none says whether the address has an
  # account:
  #
  #   :refused             "Try another email address or password."
  #   :locked, account     "Try again in a few minutes." The email's bucket
  #                        counts whether or not an account has the address,
  #                        so an address with no account locks and answers
  #                        exactly alike. The attempt that closed it is
  #                        answered so too, and so is a known device's own
  #                        bucket (`SignInCompletion::DEVICE_COOKIE`),
  #                        which only a browser that signed in to the
  #                        account meets.
  #   :locked, address     "Try again later.", as the per-address rate limit
  #                        answers: an address's bucket says nothing of an
  #                        account. It wins over the account's when an
  #                        attempt closed both, being the longer.
  #   :bot_check_*         "Complete the check, then sign in again."
  #
  # A PASSKEY SIGN-IN (`passkey_options`, `passkey`) names no account until
  # its assertion is verified, so it counts in the address's wide bucket
  # alone (`Throttle#reserve_address`) and no account's lock refuses it: a
  # passkey cannot be guessed, and a bot naming a credential must not lock
  # out its owner. It never asks for the bot check. The browser's script
  # posts the assertion as `credential` and is answered 200 JSON
  # `{ "location" }` whatever happened, so it cannot tell one refusal from
  # another: the dashboard (or the page the person was sent from) on
  # success; on a refusal (an unknown passkey, a bad signature, a challenge
  # used, late or issued for another purpose) the sign-in page with "That
  # passkey didn't work. Try again, or sign in with your password."; past
  # the wide bucket or the rate limit, the sign-in page with "Try again
  # later.". At an IP address there is no relying party (`SignIn::
  # RelyingParty`), so the page draws no passkey button and both actions
  # answer 404.
  #
  # THE BOT CHECK'S FLAG. `new` cannot know which email will be typed, so it
  # shows the check when the address's count is due or when
  # `session[:sign_in_bot_check]` says the last attempt left it due (the
  # email's count); without the flag a person whose email, not address,
  # tripped the check would be refused with nothing to answer. A success, or
  # a refusal after which nothing is due, forgets it.
  #
  # WHAT IS AUDITED, and only then. Sign-ins and sign-outs go straight
  # through `Audit.record` -- a session isn't a record any service writes.
  # `session.created`/`session.destroyed` are the user's own (actor and
  # subject both). A checked password that failed is `session.failed`, and
  # each bucket that attempt closed is one `session.locked`: neither has a
  # user to name (looking one up would make a refusal for a known address
  # cost more than for an unknown one), so both carry the email that was
  # tried in `metadata`, never the password. For the same reason the
  # account's pause mail is a job queued for any email, known or not
  # (`SignIn::LockoutMailJob`, which looks the account up); a known
  # device's lock is the person's own and mails nothing. Nor a password
  # typed into the email box by mistake: a value without an "@" isn't an address, so
  # nothing is kept; an address is cut to the 254 characters an email
  # address can have, so the log can't be stuffed through it. An attempt
  # refused by a closed bucket or the bot check records nothing: it checked
  # no password, and an event each would bury the log under a bot's run
  # (its spans carry the run instead). A refused passkey names no account
  # and no email, so it records nothing of its own (its `auth.passkey` span
  # carries it); only the wide bucket it closed is one `session.locked`. A
  # passkey's `session.created` says `{ "method" => "passkey" }`. How a
  # closed bucket is audited and mailed is `SignInLocks`', which the second
  # step shares.
  #
  # A RIGHT PASSWORD THAT OWES A SECOND PROOF (`:second_factor_required`,
  # an account holding a passkey or unused recovery codes) signs nobody in
  # and writes no known device: it holds the account in the second step's
  # cookie (`SecondFactorsController::SECOND_FACTOR_COOKIE`) and goes to
  # the second step, on its code view when the account has no passkey.
  class SessionsController < ApplicationController
    include MailLinkOrigin
    include PasskeyChallenges
    include SignInCompletion
    include SignInLocks

    layout "product"

    allow_unauthenticated_access only: %i[ new create passkey_options passkey ]
    helper_method :passkey_relying_party
    before_action :require_passkey_relying_party, only: %i[ passkey_options passkey ]

    RATE_LIMIT_PURPOSE = "content_spiel sign-in rate limit".freeze

    # Where Turnstile's script is loaded from and its widget framed from.
    BOT_CHECK_ORIGIN = "https://challenges.cloudflare.com".freeze
    # On a site with both Turnstile keys every answer of the sign-in page
    # carries a policy that lets the widget in (`allow_bot_check_origin`).
    # Declared before the rate limit's before_action, so a limited POST's
    # answer carries it too.
    before_action :allow_bot_check_origin, only: %i[ new create ], if: -> { SignIn::BotCheck.current }
    # The per-address bucket, Rails' `rate_limit`: it counts every POST to
    # `create` and `passkey`, one count shared by both, a success and a
    # refusal alike, not failures alone. Its
    # store is the throttle's (`SignIn.store`), so it counts where every
    # process sees it, and trips in tests too, whose cache is a null store.
    # Keyed as the throttle keys an address (`VisitorAddress`): an HMAC, so
    # the store holds no IP, and an IPv6 visitor by their /64, so rotating
    # within it is one visitor.
    rate_limit to: 10, within: 3.minutes, only: %i[ create passkey ], store: SignIn.store,
      by: -> { VisitorAddress.key(request.remote_ip, purpose: RATE_LIMIT_PURPOSE) }, with: -> { answer_address_limited }
    # The passkey's options, on a count of their own (`name:`), so a page's
    # fetch costs no proof, and looser than the proofs': options write
    # nothing on the server, and an office behind one address must keep its
    # passkey button. Past it, a bare 429, which the script takes as no
    # passkey to offer, and no challenge kept.
    rate_limit to: 30, within: 1.minute, only: :passkey_options, name: "options", store: SignIn.store,
      by: -> { VisitorAddress.key(request.remote_ip, purpose: RATE_LIMIT_PURPOSE) }, with: -> { head :too_many_requests }

    def new
      bot_check = SignIn::BotCheck.current
      @bot_check_configured = bot_check.present?
      @bot_check = bot_check if bot_check && (session[:sign_in_bot_check] || SignIn::Throttle.new.bot_check_due?(address: request.remote_ip))
    end

    def create
      attempt = SignIn::PasswordAttempt.new(
        email: params[:email_address], password: params[:password],
        address: request.remote_ip, hostname: request.host,
        bot_check_token: params["cf-turnstile-response"],
        device: known_device
      )
      outcome = attempt.call

      if outcome.ok?
        complete_sign_in(outcome.account, method: "password")
        redirect_to after_authentication_url
      elsif outcome.status == :second_factor_required
        session.delete(:sign_in_bot_check)
        hold_second_step(outcome.account)
        redirect_to outcome.account.passkeys.exists? ? admin_second_factor_path : admin_second_factor_path(with: "code")
      else
        if outcome.status == :refused
          Audit.record("session.failed", metadata: email_metadata(attempt.email))
          record_locks(outcome.trips, email: attempt.email, identifier: attempt.identifier)
        end
        if outcome.bot_check_due
          session[:sign_in_bot_check] = true
        else
          session.delete(:sign_in_bot_check)
        end
        redirect_to admin_sign_in_path, alert: refusal_sentence(outcome)
      end
    end

    # The options for a sign-in that names nobody (`allow` empty: the
    # browser offers any passkey of this site), and their challenge kept for
    # `passkey`.
    def passkey_options
      options, challenge = SignIn::PasskeyCheck.new(relying_party: passkey_relying_party).options(allow: [])
      issue_passkey_challenge("sign_in", challenge)
      render json: options
    end

    # The address is counted before anything is checked, and the challenge
    # is taken before the assertion is read, so a refused or a late answer
    # spends it too.
    def passkey
      throttle = SignIn::Throttle.new
      reservation = throttle.reserve_address(address: request.remote_ip)
      return answer_passkey_refused(t("admin.sessions.limited")) unless reservation.ok?

      challenge = take_passkey_challenge("sign_in")
      result = SignIn::PasskeyCheck.new(relying_party: passkey_relying_party)
        .verify(params[:credential], challenge: challenge, credentials: Passkey, ceremony: "sign_in")

      if result.ok
        throttle.release_address(address: request.remote_ip)
        complete_sign_in(result.credential.user, method: "passkey")
        render json: { location: after_authentication_url }
      else
        reservation.closes.each { |trip| Audit.record("session.locked", metadata: { "bucket" => "address_wide", "seconds" => trip.seconds }) }
        answer_passkey_refused(t("admin.sessions.passkey_failed"))
      end
    end

    def destroy
      Audit.record("session.destroyed", subject: Current.user)
      terminate_session
      redirect_to admin_sign_in_path, status: :see_other
    end

    private

    # THE POLICY BELONGS TO THE DOCUMENT. A browser takes a page's
    # Content-Security-Policy from the response that loaded the document;
    # the headers of what Turbo fetches into it (a form's answer, a visit)
    # change nothing. So widening the one answer that draws the widget is
    # not enough: the document it is drawn into must have been loaded with
    # the widened policy. On a site with both keys, therefore:
    #
    # - every answer of the sign-in page, drawn or redirected to, carries
    #   the site's policy with BOT_CHECK_ORIGIN added to `frame-src` (the
    #   widget is an iframe) and to `script-src` and `default-src` where
    #   the site sets them (it sets neither today, which leaves scripts
    #   unrestricted: a later script-src gets the origin here);
    # - the page asks Turbo to load it whole (`turbo-visit-control`
    #   `reload`, `admin/sessions/new`), so a Turbo visit from a page
    #   loaded under the site's policy (sign-out, the reset pages) becomes
    #   a full load under this one;
    # - Sign in sends the form without Turbo (`data-turbo="false"` on the
    #   submit button), so its answer is a full load too, and the redirect's
    #   flash reaches the page: a Turbo answer that reloaded would have
    #   spent the flash on the fetch it threw away.
    #
    # Without the keys none of this applies, and the page is the site's
    # policy and a Turbo form, as in development.
    def allow_bot_check_origin
      policy = current_content_security_policy
      directives = policy.directives
      policy.frame_src(*directives.fetch("frame-src", [ "'self'" ]), BOT_CHECK_ORIGIN)
      policy.script_src(*directives["script-src"], BOT_CHECK_ORIGIN) if directives.key?("script-src")
      policy.default_src(*directives["default-src"], BOT_CHECK_ORIGIN) if directives.key?("default-src")
      request.content_security_policy = policy
    end

    def refusal_sentence(outcome)
      case outcome.status
      when :bot_check_required, :bot_check_failed then t("admin.sessions.bot_check")
      else
        buckets = outcome.trips.map(&:bucket)
        if buckets.include?(:address_wide) then t("admin.sessions.limited")
        elsif buckets.intersect?([ :account, :device ]) then t("admin.sessions.locked")
        else t("admin.sessions.refused")
        end
      end
    end

    # Past the per-address rate limit: answered as the wide address bucket
    # is, inside the attempt's span with the one bucket that decided it. A
    # passkey sign-in has no `auth.sign_in` span (its ceremony is
    # `auth.passkey`), so its limit is the bucket's span alone.
    def answer_address_limited
      return limited_span { answer_passkey_refused(t("admin.sessions.limited")) } if action_name == "passkey"

      Telemetry.in_span("auth.sign_in", attributes: { "auth.method" => "password", "auth.outcome" => "locked" }) do
        limited_span { redirect_to admin_sign_in_path, alert: t("admin.sessions.limited") }
      end
    end

    def limited_span(&block)
      Telemetry.in_span("auth.throttle", attributes: { "auth.bucket" => "address", "auth.tripped" => true }) { block.call }
    end

    # Every refusal of a passkey sign-in is the same 200 JSON, back to the
    # sign-in page with one alert, so the script that posted it learns
    # nothing it could tell apart.
    def answer_passkey_refused(sentence)
      flash[:alert] = sentence
      render json: { location: admin_sign_in_path }
    end

    def require_passkey_relying_party
      head :not_found if passkey_relying_party.nil?
    end

    # The second step's cookie holds the account's id and the time,
    # encrypted and HttpOnly, never the password. It lives as long as the browser's
    # session, and the second step reads its `at` against
    # `SignIn::SECOND_STEP_LIFETIME` (`SecondFactorsController#pending_user`),
    # so a step left too long is answered "That took too long" rather than
    # vanishing into a plain sign-in page.
    def hold_second_step(user)
      cookies.encrypted[SecondFactorsController::SECOND_FACTOR_COOKIE] = {
        value: { "user_id" => user.id, "at" => Time.current.to_i },
        httponly: true, same_site: :lax, secure: request.ssl?
      }
    end
  end
end
