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
  # from Settings) lets the digest go at the next run. The failure itself is
  # mail's state, recorded at once, a connection failure too
  # (`ApplicationMailer.sent_now?`): the retries are this schedule.
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
    def initialize(now: Time.current)
      @now = now.floor(6)
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
      sent = 0
      owners.each { |owner| sent += 1 if ApplicationMailer.sent_now?(DigestMailer.digest(owner, ids), fingerprint: fingerprint) }
      sent
    ensure
      give_back(before) if sent.to_i.zero?
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
