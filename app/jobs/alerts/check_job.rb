module Alerts
  # Every minute (`config/recurring.yml`): the scan of the audit log
  # (`Alerts::Rules`), the backups' age (`Alerts::BackupRule`, so a new day's
  # alert goes in that minute's digest), then the owners' digest (`Alerts::Mailing`, which sends
  # it here and tries a failed send again on its own schedule), then the
  # prune of alerts past their keeping (`Alert.expired`).
  #
  # Each step rescues its own failure, so a scan that fails does not keep
  # the alerts already found from being mailed, nor a digest that fails the
  # prune. A failure is one log line with the step and the error's class,
  # never its message, and a report to `Rails.error`, which the alert
  # subscriber drops for a job of this namespace (`Alerts::ErrorSubscriber`):
  # a check that fails every minute while the database is down must not add
  # an alert a minute, and `/ready` is what tells a monitor.
  class CheckJob < ApplicationJob
    queue_as :default

    FAILED = "[ContentSpiel] Alert check failed at %s: %s".freeze

    def perform
      now = Time.current
      step(:rules) { Rules.new(now: now).apply }
      step(:backups) { BackupRule.new(now: now).apply }
      step(:digest) { Mailing.new(now: now).deliver }
      step(:prune) { Alert.expired(now).delete_all } # version: none (alerts are no part of a page)
      nil
    end

    private

    def step(name)
      yield
    rescue StandardError => error
      Rails.logger.error(format(FAILED, name, error.class.name))
      Rails.error.report(error, handled: true, source: "content_spiel.alerts")
    end
  end
end
