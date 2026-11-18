module Alerts
  # Reads the backups' status file (`ContentSpiel::Backup::Status`) and writes
  # the `backup_stale` alert (`Alerts::CheckJob` runs it): the newest good
  # backup is `STALE_AFTER` old, none has ever succeeded `STALE_AFTER` after
  # the first run, or the last monthly check failed. A failed run alone alerts
  # nothing: its backup step may have succeeded, and its `last_ok_at` says.
  #
  # No file, or one that cannot be read, raises nothing: System status warns,
  # and a site with no backups set up (development included) is not alerted
  # every day.
  #
  # ONE ALERT PER UTC DAY, inserted once (`insert_all`, a repeat ignored). A
  # row that was updated by every minute's run would have a `last_seen_at`
  # newer than its mail, and `Alert.due` would mail it again each hour; left
  # alone it is mailed once, and the next day's row is a new alert. Its
  # details are the fixed `reason` and the age in whole `hours` (nil for a
  # failed check) and nothing else.
  class BackupRule
    STALE_AFTER = 48.hours

    def initialize(now: Time.current, status: nil)
      @now = now
      @status = status
    end

    # Rows inserted: 1 the first time an alert is due that day, else 0.
    def apply
      status = @status || ContentSpiel::Backup::Status.read(ContentSpiel::Backup::Status.path(Rails.root))
      return 0 if status.nil? || status.unreadable?

      details = details_for(status) or return 0
      Alert.insert_all( # version: none (alerts are no part of a page)
        [ { kind: "backup_stale", fingerprint: "backup_stale|#{@now.utc.to_date.iso8601}", details:, occurrences: 1,
            first_seen_at: @now, last_seen_at: @now } ],
        unique_by: :fingerprint
      ).length
    end

    private

    def details_for(status)
      if status.last_ok_at
        age = status.good_backup_age(@now)
        return { "reason" => "stale", "hours" => hours(age) } if age >= STALE_AFTER
      elsif (age = status.since_first_run(@now)) && age >= STALE_AFTER
        return { "reason" => "never", "hours" => hours(age) }
      end

      { "reason" => "check_failed", "hours" => nil } if status.check_failed?
    end

    def hours(seconds) = (seconds / 1.hour).floor
  end
end
