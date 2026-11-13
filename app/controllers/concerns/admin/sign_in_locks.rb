module Admin
  # The buckets a refused sign-in attempt closed (`SignIn::Outcome#trips`),
  # audited and mailed one way for the password step and the second step
  # alike: each trip is one `session.locked`, and an account's is also the
  # account's pause mail.
  #
  # `session.locked` names no user (looking one up would make a refusal for
  # a known address cost more than for an unknown one), so it carries the
  # email that was tried in `metadata`, cut to MAX_EMAIL_LENGTH, and only
  # when it is an address at all: a password typed into the email box by
  # mistake has no "@" and is never kept. The pause mail is a job queued
  # for any email, known or not (`SignIn::Protection::LockoutMailJob`, which looks the
  # account up), at most once an hour per email (`Throttle#notice_due?`); a
  # known device's lock is the person's own and mails nothing.
  #
  # The including controller includes `MailLinkOrigin`.
  module SignInLocks
    # The longest an email address can be (RFC 5321's path limit), and so
    # the most of one `session.failed` or `session.locked` keeps.
    MAX_EMAIL_LENGTH = 254

    private

    # `email`: the address as tried (a String, or ""); `identifier`: the
    # account bucket's key, as the throttle counted it.
    def record_locks(trips, email:, identifier:)
      trips.each do |trip|
        Audit.record("session.locked", metadata: locked_metadata(trip, email))
        queue_lockout_mail(trip, email: email, identifier: identifier) if trip.bucket == :account
      end
    end

    def queue_lockout_mail(trip, email:, identifier:)
      Telemetry.in_span("auth.lockout_mail") do |span|
        due = SignIn::Protection::Throttle.new.notice_due?(identifier: identifier)
        if due
          SignIn::Protection::LockoutMailJob.perform_later(email, locked_at: Time.current, from_address: request.remote_ip,
            minutes: trip.seconds.fdiv(60).ceil, **mail_link_origin)
        end
        Telemetry.record(span, "auth.mail.queued" => due)
      end
    end

    def locked_metadata(trip, email)
      if trip.bucket == :account || trip.bucket == :device
        { "bucket" => trip.bucket.to_s, **email_metadata(email), "level" => trip.level, "seconds" => trip.seconds }
      else
        { "bucket" => "address_wide", "seconds" => trip.seconds }
      end
    end

    def email_metadata(email)
      email.include?("@") ? { "email_address" => email.first(MAX_EMAIL_LENGTH) } : {}
    end
  end
end
