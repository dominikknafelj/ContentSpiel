module Sso
  # Every hour (config/recurring.yml, `sso_recheck`): asks the outside
  # provider again about every session it made whose last good check is
  # `Session::PROVIDER_CHECK_EVERY` old (`Session.provider_check_due`), so a
  # person removed at the provider is out of CS Studio within a day.
  #
  # Two kinds of session are asked:
  #
  # - an SSO session with a refresh token, through `SignIn::Oidc::Refresh`
  #   with its account's `sso_subject` (Refresh draws the `auth.sso.recheck`
  #   CLIENT span of each, so none is drawn here). While no provider is
  #   configured nothing is asked, and the sessions end by `Session#expiry`;
  # - a session of a gem's method whose `SignInMethods` entry has a `recheck`,
  #   through `entry.recheck.call(session)`.
  #
  # Each answer is acted on:
  #
  # - `:ok` moves `provider_checked_at` to the run's `at`, and stores the
  #   refresh token the provider rotated to;
  # - `:revoked` ends the session (`Sessions::End`, `sso_revoked`, no actor),
  #   as does an SSO session whose account has no link any more;
  # - `:unavailable` writes nothing. THE GRACE COUNTS FROM THE LAST GOOD
  #   CHECK: a failed ask never moves the date, so a provider that stays out
  #   of reach ends the session at EVERY + GRACE (`expired_sso`, by a request
  #   or `Sessions::SweepJob`), however many runs failed before.
  #
  # A gem's recheck that raises is reported (`Rails.error.report`, handled)
  # and is `:unavailable` for that session alone, and one that answers
  # anything but the three words is `:unavailable` too, logged by its class
  # (the answer could be anything, a token among them), so no gem stops the
  # run or keeps a session alive by a wrong answer.
  #
  # ONE ASK PER SESSION, UNDER ITS LOCK. Each session is read again under
  # `FOR UPDATE SKIP LOCKED`, still due and not yet expired, and its lock is
  # held across the ask and what follows. So a second run at the same time
  # skips the row the first holds and, once the first has committed, finds it
  # not due: the refresh token is sent once (a second send of a token
  # the provider rotated would be its `invalid_grant`, and end a person still
  # at work). A session signed out or unlinked meanwhile is not found and is
  # skipped, never written back. One past its grace is not asked: an `:ok`
  # would move its date and keep alive a session that has already ended. The
  # cost is that a request touching the row (`seen!`, a sign-out) waits for
  # one ask, which `SignIn::OutsideCall` bounds, once a day per session.
  #
  # The due rows are listed by id in batches of BATCH, after the last id
  # seen, so a session left due by `:unavailable` is asked once per run.
  #
  # The run is the `auth.sso.recheck_run` span, with how many sessions were
  # asked and how each answered, and `auth.session.count`, the sessions it
  # ended. No token reaches a span, a log line or an audit event.
  class RecheckJob < ApplicationJob
    queue_as :default

    BATCH = 100
    ANSWERS = %i[ok revoked unavailable].freeze

    def perform(at: Time.current)
      Telemetry.in_span("auth.sso.recheck_run") do |span|
        @tally = Hash.new(0)
        recheck_sso(at)
        SignInMethods.entries.select(&:recheck).each { |entry| recheck_method(entry, at) }
        Telemetry.record(span, "auth.sso.recheck.checked" => @tally[:checked], "auth.sso.recheck.ok" => @tally[:ok],
          "auth.sso.recheck.revoked" => @tally[:revoked], "auth.sso.recheck.unavailable" => @tally[:unavailable],
          "auth.session.count" => @tally[:ended])
      end
    end

    private

    def recheck_sso(at)
      provider = SignIn::Oidc::Provider.current
      return unless provider

      refresh = SignIn::Oidc::Refresh.new(provider: provider)
      each_due(Session.where(authenticated_with: "sso").where.not(provider_token: nil), at) do |session|
        subject = session.user.sso_subject
        next [ :revoked, nil ] if subject.blank?

        result = refresh.call(session.provider_token, subject: subject)
        [ result.status, result.refresh_token ]
      end
    end

    def recheck_method(entry, at)
      each_due(Session.where(authenticated_with: entry.name), at) do |session|
        answer = entry.recheck.call(session)
        unless ANSWERS.include?(answer)
          Rails.logger.warn("[ContentSpiel] The recheck of sign-in method #{entry.name} answered a #{answer.class}, " \
            "not one of #{ANSWERS.join(", ")}: read as unavailable.")
          answer = :unavailable
        end
        [ answer, nil ]
      end
    end

    # Yields each due session of `scope`, locked, and acts on the
    # `[status, refresh_token]` the block answers.
    def each_due(scope, at, &ask)
      after = nil
      loop do
        ids = scope.provider_check_due(at).then { |due| after ? due.where(id: after.next..) : due }.order(:id).limit(BATCH).ids
        break if ids.empty?

        ids.each { |id| recheck_one(scope, id, at, &ask) }
        after = ids.last
      end
    end

    def recheck_one(scope, id, at, &ask)
      Session.transaction do
        session = scope.provider_check_due(at).lock("FOR UPDATE SKIP LOCKED").find_by(id: id)
        next if session.nil? || session.expiry(at)

        @tally[:checked] += 1
        status, token = asked(session, &ask)
        @tally[status] += 1
        case status
        when :ok
          changes = { provider_checked_at: at }
          changes[:provider_token] = token if token && token != session.provider_token
          session.update_columns(changes) # version: none (a session is on no public page)
        when :revoked
          Sessions::End.call(session, reason: "sso_revoked", actor: nil)
          @tally[:ended] += 1
        end
      end
    end

    # The ask runs in a savepoint, so one that raises after a statement of its
    # own failed leaves the run's transaction usable.
    def asked(session, &ask)
      Session.transaction(requires_new: true) { ask.call(session) }
    rescue StandardError => error
      Rails.error.report(error, handled: true)
      Rails.logger.warn("[ContentSpiel] A session's re-check raised #{error.class}: read as unavailable.")
      [ :unavailable, nil ]
    end
  end
end
