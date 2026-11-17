module Alerts
  # Mails the owners the alerts they have not been told of: one
  # `Alerts::DigestMailer#digest` per owner, at most one digest every
  # `Alert::DIGEST_EVERY` (measured from the newest `mailed_at` of any alert),
  # and an alert seen again after its mail once that mail is
  # `Alert::REMIND_AFTER` old (`Alert.due`).
  #
  # NOTHING IS MARKED THAT CANNOT GO. While outgoing mail is not set up or
  # saved but not tested (`MailSettings#state`), or no origin is known for
  # the mail's link (`ApplicationMailer.link_url_options`, the rule every
  # mailed link follows), nothing is sent and no alert is marked, so the
  # alerts wait for the first run that can mail them and System status says
  # they were not mailed. One line says why, at most once an hour (a mark in
  # `CounterStore`, as sign-in's pause notice keeps it; a store that fails
  # logs the line again rather than lose it).
  #
  # A FAILED SEND IS TRIED AGAIN BY THE DIGEST ITSELF, never left to wait for
  # some other mail to succeed: one passing failure of the server must not
  # silence every alert after it. A send that reached no owner gives its
  # alerts back as they were and records on them how many sends failed in a
  # row and when the last did (`digest_failures`, `digest_failed_at`); while
  # mail's state is `:failed`, the next try waits `RETRY_AFTER` after that
  # failure: 10 minutes after the first, 30 after the second, an hour after
  # every one since, never longer while alerts wait. A send that went out
  # puts both back and, as any mail that goes out, makes mail working again
  # (`MailSettings.record_success!`). Mail working again first (a test mail
  # from Settings) lets the digest go at the next run.
  #
  # A CONNECTION FAILURE IS TRIED AGAIN AT ONCE, as `MailDeliveryJob` tries a
  # queued mail: up to its `ATTEMPTS` (four in all) for its list of
  # passing errors (`MailFailure::CONNECTION_ERRORS`), `ATTEMPT_WAITS` apart
  # (1, 2 and 3 seconds), and recorded as mail's state, and as the digest's
  # failure, only after the last: one blip the next attempt gets through
  # must not put "Last send failed" on Settings and System status. Any other
  # failure (a refused login, a refused sender) is recorded at once and not
  # tried again. The check job runs every minute, so the attempts are kept
  # well inside one: no attempt begins after `SEND_BUDGET`, 20 seconds, of
  # this run's sending (that one is its last), and a server that failed every
  # attempt is not asked again for the next owner. With the mail settings'
  # timeouts (`MailSettings::OPEN_TIMEOUT`, `READ_TIMEOUT`) a run that meets
  # a server that never answers ends in about 35 seconds.
  #
  # SENT, NOT QUEUED. The digest is delivered here, in the check job, and not
  # through `MailDeliveryJob`, because an alert is marked mailed only by a
  # send that went out, and only this job knows its alerts. The mailer is
  # handed the owner and the alerts' ids, never their details.
  #
  # MARKED WHILE SENT. The alerts are marked `mailed_at` in one statement
  # (a job's write, as mail's state columns are, with no audit event:
  # `Alerts::Alert`) before the send, and given back, each to the
  # `mailed_at` it had, when the send reached no owner or raised: a mark
  # that stands is a mail that went out to at least one owner (one owner's
  # address refused does not mail the others again every hour). While the
  # send runs, the mark is what makes the next minute's run find it too soon.
  #
  # ONE DIGEST FOR TWO RUNS AT ONCE. The mark takes only alerts that are
  # still due (`Alert.due`), so a run that started before another's mark
  # finds those rows taken, marks none of them, and sends only what it
  # marked itself (`claim`): two check runs overlapping, a slow one and the
  # next minute's, never mail the same alert twice.
  class Mailing
    NOT_READY = "[ContentSpiel] An alert digest was not sent: mail is not ready.".freeze
    NO_ADDRESS = "[ContentSpiel] An alert digest was not sent: no site address is known. Set PUBLIC_HOST.".freeze
    RETRYING = "[ContentSpiel] An alert digest was not sent: the send failed. It is tried again in %d minutes.".freeze
    # Why no digest goes, by the mail's state (`MailSettings::STATES`):
    # every state but `:working`, as System status says it.
    MAIL_STATES = { not_set_up: :mail_not_set_up, untested: :mail_untested, failed: :mail_failed }.freeze
    # The states that hold the digest: a failed one is tried again instead.
    HELD = MAIL_STATES.except(:failed).freeze
    SKIPPED_LINES = HELD.values.index_with(NOT_READY).merge(no_address: NO_ADDRESS).freeze
    # How often a skipped digest's line is logged.
    SKIPPED_LOGGED_EVERY = 1.hour
    # How long after its last failure the digest is tried again, by how many
    # sends failed in a row: the last figure for every one past them.
    RETRY_AFTER = [ 10.minutes, 30.minutes, 1.hour ].freeze
    # The attempts of one owner's send within a run, as a queued mail's.
    ATTEMPTS = MailDeliveryJob::ATTEMPTS
    # The waits between them, in seconds: one fewer than the attempts.
    ATTEMPT_WAITS = [ 1, 2, 3 ].freeze
    # No attempt begins after this many seconds of a run's sending.
    SEND_BUDGET = 20

    # Why no digest can go now, as System status says it: nil when one can;
    # while outgoing mail is not working, its state's reason (`MAIL_STATES`:
    # `:mail_not_set_up`, `:mail_untested`, `:mail_failed`, read from
    # `MailSettings#state`, the one source of mail's state); else
    # `:no_address` while no origin is known for the mail's link (asked as a
    # job asks, with no request). Any mail state but working wins over the
    # missing address: it is the first thing to fix.
    #
    # `:mail_failed` does not hold `deliver` (`held_by`): the alerts wait,
    # unmailed, until a send of their digest goes out, which the digest
    # tries itself (`RETRY_AFTER`).
    def self.blocked_by
      blocked = MAIL_STATES[MailSettings.current.state]
      return blocked if blocked

      :no_address if DigestMailer.link_url_options.empty?
    end

    # What holds the digest from even trying: `blocked_by` but a failed send.
    def self.held_by
      held = HELD[MailSettings.current.state]
      return held if held

      :no_address if DigestMailer.link_url_options.empty?
    end

    def self.retry_after(failures) = RETRY_AFTER[failures.clamp(1, RETRY_AFTER.size) - 1]

    # `now` to the microsecond, the column's precision, so the claim reads
    # back exactly the rows it wrote.
    # `wait` sleeps between attempts; a test hands one that only records.
    def initialize(now: Time.current, wait: ->(seconds) { sleep(seconds) })
      @now = now.floor(6)
      @wait = wait
    end

    # Sends the digests that are due; answers how many mails went out.
    def deliver
      return 0 if too_soon?

      ids = pending_ids
      return 0 if ids.empty?
      held_by = self.class.held_by
      return skipped(held_by) if held_by
      return 0 if retry_waiting?(ids)

      owners = User.owners.to_a
      return 0 if owners.empty?

      before = Alert.where(id: ids).pluck(:id, :mailed_at, :digest_failures)
      ids = claim(ids)
      return 0 if ids.empty?

      send_digests(owners, ids, before.select { |id, *| ids.include?(id) })
    end

    private

    # The due alerts' ids, newest seen first.
    def pending_ids = Alert.due(@now).order(last_seen_at: :desc, id: :desc).pluck(:id)

    # Marks those of `ids` that are still due as mailed now, with no failed
    # send, and answers the ids this call marked, in the order given: a run
    # at the same time that marked one first keeps it.
    def claim(ids)
      marked = Alert.due(@now).where(id: ids).update_all(mailed_at: @now, digest_failures: 0, digest_failed_at: nil, updated_at: @now) # version: none (alerts are no part of a page)
      return [] if marked.zero?

      mine = Alert.where(id: ids, mailed_at: @now).pluck(:id)
      ids & mine
    end

    # Sends each owner the digest; when none went out (or one raised), gives
    # the alerts back. Answers how many went out.
    def send_digests(owners, ids, before)
      fingerprint = MailSettings.current.fingerprint
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @unreachable = false
      sent = 0
      owners.each do |owner|
        break if @unreachable

        sent += 1 if send_one(owner, ids, fingerprint)
      end
      sent
    ensure
      give_back(before) if sent.to_i.zero?
    end

    # One owner's digest, tried again on a connection failure while attempts
    # and the run's budget last; a send whose last attempt followed a
    # connection failure and failed too leaves the server unreachable.
    def send_one(owner, ids, fingerprint)
      attempt = 1
      begin
        final = attempt >= ATTEMPTS || out_of_time?(ATTEMPT_WAITS[attempt - 1])
        ApplicationMailer.sent_now?(DigestMailer.digest(owner, ids), fingerprint: fingerprint, final_attempt: final).tap do |sent|
          @unreachable = true if !sent && attempt > 1
        end
      rescue ApplicationMailer::TryAgain
        @wait.call(ATTEMPT_WAITS[attempt - 1])
        attempt += 1
        retry
      end
    end

    # Whether waiting `seconds` would begin the next attempt past the budget.
    def out_of_time?(seconds)
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started + seconds.to_i > SEND_BUDGET
    end

    # Each alert back to the `mailed_at` it had, one more failed send in a
    # row on all of them (the most any of them had, plus this one), and now
    # as the last failure. Only the rows this run still holds as its own.
    def give_back(before)
      failures = before.map(&:last).max.to_i + 1
      before.group_by { |_id, mailed_at, _| mailed_at }.each do |mailed_at, rows|
        Alert.where(id: rows.map(&:first), mailed_at: @now)
          .update_all(mailed_at: mailed_at, digest_failures: failures, digest_failed_at: @now, updated_at: @now) # version: none (alerts are no part of a page)
      end
      Rails.logger.warn(format(RETRYING, self.class.retry_after(failures).in_minutes.to_i))
    end

    # While the last send failed, the digest waits `RETRY_AFTER` after its
    # own last failure. Mail working again (another mail went out) ends the
    # wait; alerts no digest has failed for go at once.
    def retry_waiting?(ids)
      return false unless MailSettings.current.state == :failed

      waiting = Alert.where(id: ids)
      failures = waiting.maximum(:digest_failures).to_i
      return false if failures.zero?

      last = waiting.maximum(:digest_failed_at)
      !last.nil? && @now < last + self.class.retry_after(failures)
    end

    def too_soon?
      last = Alert.last_mailed_at
      !last.nil? && last > @now - Alert::DIGEST_EVERY
    end

    def skipped(reason)
      Rails.logger.warn(SKIPPED_LINES.fetch(reason)) if skipped_line_due?(reason)
      0
    end

    def skipped_line_due?(reason)
      CounterStore.current.write("alerts:digest_skipped:#{reason}", true, unless_exist: true, expires_in: SKIPPED_LOGGED_EVERY) ? true : false
    rescue StandardError
      true
    end
  end
end
