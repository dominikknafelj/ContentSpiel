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
  #                        bucket (`DEVICE_COOKIE`), which only a browser
  #                        that signed in to the account meets.
  #   :locked, address     "Try again later.", as the per-address rate limit
  #                        answers: an address's bucket says nothing of an
  #                        account. It wins over the account's when an
  #                        attempt closed both, being the longer.
  #   :bot_check_*         "Complete the check, then sign in again."
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
  # (its spans carry the run instead).
  class SessionsController < ApplicationController
    include MailLinkOrigin

    layout "product"

    # The longest an email address can be (RFC 5321's path limit), and so
    # the most of one `session.failed` or `session.locked` keeps.
    MAX_EMAIL_LENGTH = 254

    allow_unauthenticated_access only: %i[ new create ]

    RATE_LIMIT_PURPOSE = "content_spiel sign-in rate limit".freeze

    # THE KNOWN DEVICE (`SignIn::KnownDevice`): written after a right
    # password only, so a bot never holds one, and read back on every
    # attempt, so a browser that signed in to an account before is counted
    # apart from the account's bucket a bot may hold closed. Encrypted and
    # signed (`cookies.encrypted`): a cookie that does not open, or that
    # names another account, is no known device and the attempt goes the
    # common way. HttpOnly, SameSite Lax, Secure where the site is HTTPS,
    # for DEVICE_LIFETIME from its last sign-in. It holds a random id and
    # the HMACs of the accounts, never an email.
    DEVICE_COOKIE = :cs_known_device
    DEVICE_LIFETIME = 90.days

    # Where Turnstile's script is loaded from and its widget framed from.
    BOT_CHECK_ORIGIN = "https://challenges.cloudflare.com".freeze
    # On a site with both Turnstile keys every answer of the sign-in page
    # carries a policy that lets the widget in (`allow_bot_check_origin`).
    # Declared before the rate limit's before_action, so a limited POST's
    # answer carries it too.
    before_action :allow_bot_check_origin, only: %i[ new create ], if: -> { SignIn::BotCheck.current }
    # The per-address bucket, Rails' `rate_limit`: it counts every POST to
    # `create`, a success and a refusal alike, not failures alone. Its
    # store is the throttle's (`SignIn.store`), so it counts where every
    # process sees it, and trips in tests too, whose cache is a null store.
    # Keyed as the throttle keys an address (`VisitorAddress`): an HMAC, so
    # the store holds no IP, and an IPv6 visitor by their /64, so rotating
    # within it is one visitor.
    rate_limit to: 10, within: 3.minutes, only: :create, store: SignIn.store,
      by: -> { VisitorAddress.key(request.remote_ip, purpose: RATE_LIMIT_PURPOSE) }, with: -> { answer_address_limited }

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
        session.delete(:sign_in_bot_check)
        start_new_session_for outcome.account
        remember_device(attempt.identifier)
        Current.actor = outcome.account
        Audit.record("session.created", subject: outcome.account)
        redirect_to after_authentication_url
      else
        if outcome.status == :refused
          Audit.record("session.failed", metadata: email_metadata(attempt.email))
          outcome.trips.each do |trip|
            Audit.record("session.locked", metadata: locked_metadata(trip, attempt.email))
            queue_lockout_mail(trip, attempt) if trip.bucket == :account
          end
        end
        if outcome.bot_check_due
          session[:sign_in_bot_check] = true
        else
          session.delete(:sign_in_bot_check)
        end
        redirect_to admin_sign_in_path, alert: refusal_sentence(outcome)
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
    # is, inside the attempt's span with the one bucket that decided it.
    def answer_address_limited
      Telemetry.in_span("auth.sign_in", attributes: { "auth.method" => "password", "auth.outcome" => "locked" }) do
        Telemetry.in_span("auth.throttle", attributes: { "auth.bucket" => "address", "auth.tripped" => true }) do
          redirect_to admin_sign_in_path, alert: t("admin.sessions.limited")
        end
      end
    end

    # The account's pause mail, at most once an hour per email
    # (`Throttle#notice_due?` writes the hour's mark). Queued for an email
    # with no account as for one with an account: the job looks the account
    # up, so both do the same work here, a cache write and an enqueue.
    def queue_lockout_mail(trip, attempt)
      Telemetry.in_span("auth.lockout_mail") do |span|
        due = SignIn::Throttle.new.notice_due?(identifier: attempt.identifier)
        if due
          SignIn::LockoutMailJob.perform_later(attempt.email, locked_at: Time.current, from_address: request.remote_ip,
            minutes: trip.seconds.fdiv(60).ceil, **mail_link_origin)
        end
        Telemetry.record(span, "auth.mail.queued" => due)
      end
    end

    def known_device = SignIn::KnownDevice.read(cookies.encrypted[DEVICE_COOKIE])

    def remember_device(identifier)
      cookies.encrypted[DEVICE_COOKIE] = {
        value: known_device.remember(identifier).to_h,
        expires: DEVICE_LIFETIME, httponly: true, same_site: :lax, secure: request.ssl?
      }
    end

    def locked_metadata(trip, email)
      if trip.bucket == :account || trip.bucket == :device
        { "bucket" => trip.bucket.to_s, **email_metadata(email), "level" => trip.level, "seconds" => trip.seconds }
      else
        { "bucket" => "address_wide", "seconds" => trip.seconds }
      end
    end

    # `email` is the attempt's (`SignIn::PasswordAttempt#email`): a String
    # Postgres takes, or "".
    def email_metadata(email)
      email.include?("@") ? { "email_address" => email.first(MAX_EMAIL_LENGTH) } : {}
    end
  end
end
