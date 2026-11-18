require "json"
require "time"
require "pathname"
require_relative "status"

module ContentSpiel
  class Backup
    # What the backup accessory runs, one JSON file `bin/backup schedule`
    # writes when it starts, beside the status file (so in the one folder the
    # command writes in the files volume, and excluded from the backup with
    # it). System status compares the site's version with this file's, and
    # with the status file's only when this one cannot be read: the status
    # file says which version made the last run, so after `kamal accessory
    # reboot backup` it would name the old version until the next run, where
    # this file names the new one from the start. System status and the
    # backup alert read the cadence from it too, since BACKUP_EVERY is the
    # accessory's variable and the web container never has it.
    # It holds the version, the start's time and the hours between runs,
    # nothing else: no secret, no destination. Plain Ruby, standard library
    # only, like Status.
    RunningVersion = Data.define(:cms_version, :started_at, :every_hours) do
      # The cadence a reader assumes with no file, or with one whose
      # every_hours is missing or not one of Backup's EVERY_HOURS: once a day.
      const_set(:DEFAULT_EVERY, 24)
      const_set(:EVERY_HOURS, [ 1, 2, 3, 4, 6, 8, 12, 24 ].freeze)

      def self.path(root) = Pathname(root).join("storage", Status::DIRECTORY, "accessory.json")

      # nil: no file, or one that is not this JSON (a version that is not a
      # non-empty String, a time that is not ISO 8601). Either way System
      # status falls back to the status file's version. An every_hours that
      # is missing or not one it knows reads as DEFAULT_EVERY, the version
      # still read.
      def self.read(path)
        data = JSON.parse(Pathname(path).read)
        return unless data.is_a?(Hash)

        version = data["cms_version"]
        return unless version.is_a?(String) && !version.strip.empty?

        started = data["started_at"]
        new(cms_version: version, started_at: started && Time.iso8601(started).utc, every_hours: every(data["every_hours"]))
      rescue JSON::ParserError, SystemCallError, ArgumentError, TypeError, EncodingError
        nil
      end

      # The hours between runs a reader counts with: the file's, or
      # DEFAULT_EVERY for anything that is not a RunningVersion (no file,
      # an unreadable one).
      def self.every_hours_of(running)
        running.is_a?(self) ? running.every_hours : self::DEFAULT_EVERY
      end

      def self.every(value) = value.is_a?(Integer) && self::EVERY_HOURS.include?(value) ? value : self::DEFAULT_EVERY

      def write(path)
        Status.write_json(path, { "cms_version" => cms_version, "started_at" => started_at&.utc&.iso8601,
                                  "every_hours" => every_hours })
      end
    end
  end
end
