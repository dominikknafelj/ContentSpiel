module Alerts
  # Mails the owners the alerts they have not been told of: one
  # `Alerts::DigestMailer#digest` per owner, at most one digest every
  # `Alert::DIGEST_EVERY` (measured from the newest `mailed_at` of any alert),
  # and an alert seen again after its mail once that mail is
  # `Alert::REMIND_AFTER` old (`Alert.due`).
  #
  # NOTHING IS MARKED THAT CANNOT GO. While mail is not ready, or no origin
  # is known for the mail's link (`ApplicationMailer.link_url_options`, the
  # rule every mailed link follows), nothing is queued and no alert is
  # marked, so the alerts wait for the first run that can mail them and
  # System status says they were not mailed. One line says why, at most once
  # an hour (a mark in `CounterStore`, as sign-in's pause notice keeps it;
  # a store that fails logs the line again rather than lose it).
  #
  # The mailer is handed the owner and the alerts' ids, never their details:
  # a job's arguments are written to the queue's row and Active Job's log.
  #
  # MARKED, THEN QUEUED. The alerts are marked `mailed_at` in one statement
  # (a job's write, as mail's state columns are, with no audit event:
  # `Alerts::Alert`) before the mails are queued. A queue write that fails
  # after the mark loses one digest, whose alerts System status still shows
  # and whose next occurrence mails again; queued first, a mark that failed
  # would leave them due and mail them again every minute.
  #
  # ONE DIGEST FOR TWO RUNS AT ONCE. The mark takes only alerts that are
  # still due (`Alert.due`), so a run that started before another's mark
  # finds those rows taken, marks none of them, and queues only what it
  # marked itself (`claim`): two check runs overlapping, a slow one and the
  # next minute's, never mail the same alert twice.
  class Mailing
    NOT_READY = "[ContentSpiel] An alert digest was not sent: mail is not ready.".freeze
    NO_ADDRESS = "[ContentSpiel] An alert digest was not sent: no site address is known. Set PUBLIC_HOST.".freeze
    # How often a skipped digest's line is logged.
    SKIPPED_LOGGED_EVERY = 1.hour

    # `now` to the microsecond, the column's precision, so the claim reads
    # back exactly the rows it wrote.
    def initialize(now: Time.current)
      @now = now.floor(6)
    end

    # Queues the digests that are due; answers how many mails were queued.
    def deliver
      return 0 if too_soon?

      ids = pending_ids
      return 0 if ids.empty?
      return skipped(:not_ready, NOT_READY) unless MailSettings.current.ready?
      return skipped(:no_address, NO_ADDRESS) if DigestMailer.link_url_options.empty?

      owners = User.owners.to_a
      return 0 if owners.empty?

      ids = claim(ids)
      return 0 if ids.empty?

      owners.each { |owner| ApplicationMailer.queue(DigestMailer, :digest, owner, ids) }
      owners.size
    end

    private

    # The due alerts' ids, newest seen first.
    def pending_ids = Alert.due(@now).order(last_seen_at: :desc, id: :desc).pluck(:id)

    # Marks those of `ids` that are still due as mailed now, and answers the
    # ids this call marked, in the order given: a run at the same time that
    # marked one first keeps it.
    def claim(ids)
      marked = Alert.due(@now).where(id: ids).update_all(mailed_at: @now, updated_at: @now) # version: none (alerts are no part of a page)
      return [] if marked.zero?

      mine = Alert.where(id: ids, mailed_at: @now).pluck(:id)
      ids & mine
    end

    def too_soon?
      last = Alert.last_mailed_at
      !last.nil? && last > @now - Alert::DIGEST_EVERY
    end

    def skipped(reason, line)
      Rails.logger.warn(line) if skipped_line_due?(reason)
      0
    end

    def skipped_line_due?(reason)
      CounterStore.current.write("alerts:digest_skipped:#{reason}", true, unless_exist: true, expires_in: SKIPPED_LOGGED_EVERY) ? true : false
    rescue StandardError
      true
    end
  end
end
