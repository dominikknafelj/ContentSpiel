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
  # The alerts are marked `mailed_at` in one statement, a job's write as
  # mail's state columns are, with no audit event (`Alerts::Alert`).
  #
  # The name shadows the standard library's `Digest` for every bare
  # reference inside `module Alerts`: code there writes `::Digest::SHA256`.
  class Digest
    NOT_READY = "[ContentSpiel] An alert digest was not sent: mail is not ready.".freeze
    NO_ADDRESS = "[ContentSpiel] An alert digest was not sent: no site address is known. Set PUBLIC_HOST.".freeze
    # How often a skipped digest's line is logged.
    SKIPPED_LOGGED_EVERY = 1.hour

    def initialize(now: Time.current)
      @now = now
    end

    # Queues the digests that are due; answers how many mails were queued.
    def deliver
      return 0 if too_soon?

      ids = Alert.due(@now).order(last_seen_at: :desc, id: :desc).pluck(:id)
      return 0 if ids.empty?
      return skipped(:not_ready, NOT_READY) unless MailSettings.current.ready?
      return skipped(:no_address, NO_ADDRESS) if DigestMailer.link_url_options.empty?

      owners = User.owners.to_a
      return 0 if owners.empty?

      Alert.where(id: ids).update_all(mailed_at: @now, updated_at: @now) # version: none (alerts are no part of a page)
      owners.each { |owner| ApplicationMailer.queue(DigestMailer, :digest, owner, ids) }
      owners.size
    end

    private

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
