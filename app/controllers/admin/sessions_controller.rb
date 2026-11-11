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
  #                        answered so too.
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
  # (`SignIn::LockoutMailJob`, which looks the account up). Nor a password typed into the
  # email box by mistake: a value without an "@" isn't an address, so
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
    # The per-address bucket, Rails' `rate_limit`: it counts every POST to
    # `create`, a success and a refusal alike, not failures alone. Its
    # store is the throttle's (`SignIn.store`), so it counts where every
    # process sees it, and trips in tests too, whose cache is a null store.
    rate_limit to: 10, within: 3.minutes, only: :create, store: SignIn.store, with: -> { answer_address_limited }

    def new
      bot_check = SignIn::BotCheck.current
      @bot_check = bot_check if bot_check && (session[:sign_in_bot_check] || SignIn::Throttle.new.bot_check_due?(address: request.remote_ip))
    end

    def create
      attempt = SignIn::PasswordAttempt.new(
        email: params[:email_address], password: params[:password],
        address: request.remote_ip, hostname: request.host,
        bot_check_token: params["cf-turnstile-response"]
      )
      outcome = attempt.call

      if outcome.ok?
        session.delete(:sign_in_bot_check)
        start_new_session_for outcome.account
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

    def refusal_sentence(outcome)
      case outcome.status
      when :bot_check_required, :bot_check_failed then t("admin.sessions.bot_check")
      else
        buckets = outcome.trips.map(&:bucket)
        if buckets.include?(:address_wide) then t("admin.sessions.limited")
        elsif buckets.include?(:account) then t("admin.sessions.locked")
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

    def locked_metadata(trip, email)
      if trip.bucket == :account
        { "bucket" => "account", **email_metadata(email), "level" => trip.level, "seconds" => trip.seconds }
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
