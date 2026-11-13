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
  #   through `entry.recheck.call(session)`, given GEM_RECHECK_LIMIT.
  #
  # Each answer is acted on:
  #
  # - `:ok` moves `provider_checked_at` to the run's `at`, and stores the
  #   refresh token the provider rotated to, in the same statement;
  # - `:revoked` ends the session (`Sessions::End`, `sso_revoked`, no actor),
  #   as does an SSO session whose account has no link any more;
  # - `:unavailable` writes nothing. THE GRACE COUNTS FROM THE LAST GOOD
  #   CHECK: a failed ask never moves the date, so a provider that stays out
  #   of reach ends the session at EVERY + GRACE (`expired_sso`, by a request
  #   or `Sessions::SweepJob`), however many runs failed before.
  #
  # An ask that raises is `:unavailable` for that session alone and never
  # stops the run: a gem's recheck that raised or ran past its limit, and an
  # SSO session whose token cannot be decrypted because the site's encryption
  # keys are gone (it then ends at EVERY + GRACE, as an unreachable provider's
  # does). It is reported as `RecheckFailed`, naming the error's class and
  # never its message, which a gem's error could fill with its token. A
  # recheck that answers anything but the three words is `:unavailable` too,
  # logged by its class (the answer itself could be a token).
  #
  # NO LOCK OR TRANSACTION IS HELD ACROSS AN ASK. Per session, on one
  # connection (`with_connection`, so the advisory lock and its release are
  # the same database session's):
  #
  # 1. a session-level advisory lock on (ADVISORY_NAMESPACE, the id) is TRIED,
  #    and a session whose lock another run holds is skipped, so of two runs
  #    at once one asks: a refresh token is sent once, since a second send of
  #    a token the provider rotated would be its `invalid_grant`, and end a
  #    person still at work;
  # 2. the row is read again, outside any transaction: one signed out or
  #    unlinked meanwhile, not due, or past an expiry is not asked (an `:ok`
  #    would move its date and keep alive a session already over);
  # 3. the ask runs with nothing open;
  # 4. one short transaction reads the row `FOR UPDATE` and writes only when
  #    it still stands, is not expired, and its `provider_checked_at` and
  #    stored token are the ones read in 2; otherwise the answer is dropped;
  # 5. the advisory lock is released in an `ensure`.
  #
  # So a request that touches the row (`seen!`, a sign-out, `Sessions::End`)
  # waits at most for that short write, never for a provider. Only this job
  # writes `provider_token`, so the token sent is the token stored.
  #
  # A ROTATION CAN STILL BE LOST. When the provider rotated the token and the
  # write in 4 then fails (a lost connection, a crash), the provider holds the
  # new token and the row the old one, and the next run's `invalid_grant`
  # ends a live session as `sso_revoked`. No order of writes avoids it with a
  # provider that rotates; it is the one way such a revocation comes about.
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

    # The first key of the two-key advisory lock: this job's own, so its
    # locks meet no other user of advisory locks. The second key is the
    # session's id folded into Postgres' int4; two ids that fold together
    # only make one of them wait for the next run.
    ADVISORY_NAMESPACE = 0x550C2EC4
    INT4 = 2**31

    # How long a gem's recheck may take. `Timeout.timeout` interrupts the
    # gem's code wherever it is, which is acceptable here because nothing of
    # the job's is open around it (no transaction, no row lock; the advisory
    # lock is released in an `ensure`), and a recheck is a read of the gem's
    # provider whose only result the job uses is its answer. Past it the
    # session is `:unavailable`.
    GEM_RECHECK_LIMIT = 10.seconds

    # What is reported for an ask that raised: the error's class alone.
    class RecheckFailed < StandardError; end

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
        answer = Timeout.timeout(GEM_RECHECK_LIMIT) { entry.recheck.call(session) }
        unless ANSWERS.include?(answer)
          Rails.logger.warn("[ContentSpiel] The recheck of sign-in method #{entry.name} answered a #{answer.class}, " \
            "not one of #{ANSWERS.join(", ")}: read as unavailable.")
          answer = :unavailable
        end
        [ answer, nil ]
      end
    end

    # Asks each due session of `scope` through the block, which answers
    # `[status, refresh_token]`.
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
      Session.connection_pool.with_connection do |connection|
        next unless try_lock(connection, id)

        begin
          session = scope.provider_check_due(at).find_by(id: id)
          next if session.nil? || session.expiry(at)

          # Taken before the ask, which is handed the record and may change it.
          read = { checked_at: session.provider_checked_at, token: session.read_attribute_before_type_cast(:provider_token) }
          @tally[:checked] += 1
          status, token = asked(session, &ask)
          @tally[status] += 1
          write(session.id, read, status, token, at) unless status == :unavailable
        ensure
          unlock(connection, id)
        end
      end
    end

    def asked(session, &ask)
      ask.call(session)
    rescue StandardError => error
      Rails.error.report(RecheckFailed.new(error.class.name), handled: true)
      Rails.logger.warn("[ContentSpiel] A session's re-check raised #{error.class}: read as unavailable.")
      [ :unavailable, nil ]
    end

    # The token is written only when the provider rotated it (`Refresh`
    # answers the one sent otherwise); the stored ciphertext is compared, so
    # the row is unchanged since the ask's read.
    def write(id, read, status, token, at)
      Session.transaction do
        row = Session.lock.find_by(id: id)
        next if row.nil? || row.expiry(at) || row.provider_checked_at != read[:checked_at] ||
          row.read_attribute_before_type_cast(:provider_token) != read[:token]

        if status == :ok
          changes = { provider_checked_at: at }
          changes[:provider_token] = token if token && token != row.provider_token
          row.update_columns(changes) # version: none (a session is on no public page)
        else
          Sessions::End.call(row, reason: "sso_revoked", actor: nil)
          @tally[:ended] += 1
        end
      end
    end

    def try_lock(connection, id)
      # sql: Arel has no node for Postgres' advisory lock functions
      connection.select_value(Session.sanitize_sql_array([ "SELECT pg_try_advisory_lock(?, ?)", ADVISORY_NAMESPACE, id % INT4 ]))
    end

    def unlock(connection, id)
      # sql: Arel has no node for Postgres' advisory lock functions
      connection.select_value(Session.sanitize_sql_array([ "SELECT pg_advisory_unlock(?, ?)", ADVISORY_NAMESPACE, id % INT4 ]))
    end
  end
end
