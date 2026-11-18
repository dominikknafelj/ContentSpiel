require "json"
require "time"
require "pathname"
require_relative "status"

module ContentSpiel
  class Backup
    # The version the backup accessory runs, one JSON file `bin/backup
    # schedule` writes when it starts, beside the status file (so in the one
    # folder the command writes in the files volume, and excluded from the
    # backup with it). System status compares the site's version with this
    # file's, and with the status file's only when this one cannot be read:
    # the status file says which version made the last run, so after
    # `kamal accessory reboot backup` it would name the old version until the
    # next day's run, where this file names the new one from the start.
    # It holds the version and the start's time, nothing else: no secret, no
    # destination. Plain Ruby, standard library only, like Status.
    RunningVersion = Data.define(:cms_version, :started_at) do
      def self.path(root) = Pathname(root).join("storage", Status::DIRECTORY, "accessory.json")

      # nil: no file, or one that is not this JSON (a version that is not a
      # non-empty String, a time that is not ISO 8601). Either way System
      # status falls back to the status file's version.
      def self.read(path)
        data = JSON.parse(Pathname(path).read)
        return unless data.is_a?(Hash)

        version = data["cms_version"]
        return unless version.is_a?(String) && !version.strip.empty?

        started = data["started_at"]
        new(cms_version: version, started_at: started && Time.iso8601(started).utc)
      rescue JSON::ParserError, SystemCallError, ArgumentError, TypeError, EncodingError
        nil
      end

      def write(path)
        Status.write_json(path, { "cms_version" => cms_version, "started_at" => started_at&.utc&.iso8601 })
      end
    end
  end
end
