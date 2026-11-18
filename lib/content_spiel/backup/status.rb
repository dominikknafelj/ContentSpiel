require "json"
require "time"
require "pathname"
require "fileutils"
require_relative "failure"

module ContentSpiel
  class Backup
    # The status of the backups, one JSON file the backup accessory writes
    # (bin/backup) and System status and the backup alert read. It holds no
    # secret, no destination and no tool message: a failure is one of
    # Failure::REASONS. Plain Ruby, standard library only, so bin/backup loads
    # it without Rails.
    Status = Data.define(:finished_at, :outcome, :snapshot, :database_bytes, :files_bytes,
      :duration_seconds, :first_run_at, :last_ok_at, :last_check_at, :last_check_outcome,
      :check_error, :error, :cms_version) do
      # The folder under storage that holds the file; the backup excludes it.
      const_set(:DIRECTORY, "backup")
      const_set(:OUTCOMES, %w[ok failed unreadable].freeze)
      const_set(:CHECK_OUTCOMES, %w[ok failed].freeze)
      const_set(:TIMES, %i[finished_at first_run_at last_ok_at last_check_at].freeze)

      def self.path(root) = Pathname(root).join("storage", self::DIRECTORY, "status.json")

      def self.unreadable = new(**members.to_h { |m| [ m, nil ] }, outcome: "unreadable")

      # nil: no file. A file that is not this JSON, or names an unknown
      # outcome or reason, is unreadable.
      def self.read(path)
        parse(JSON.parse(Pathname(path).read))
      rescue Errno::ENOENT
        nil
      rescue JSON::ParserError, SystemCallError, ArgumentError, TypeError, EncodingError
        unreadable
      end

      def self.parse(data)
        return unreadable unless data.is_a?(Hash)

        values = members.to_h { |m| [ m, data[m.to_s] ] }
        self::TIMES.each { |m| values[m] = Time.iso8601(values[m]).utc if values[m] }
        return unreadable unless self::OUTCOMES.include?(values[:outcome]) && values[:outcome] != "unreadable"
        return unreadable unless values[:last_check_outcome].nil? || self::CHECK_OUTCOMES.include?(values[:last_check_outcome])
        return unreadable unless [ values[:error], values[:check_error] ].all? { |r| r.nil? || Failure::REASONS.include?(r) }

        return unreadable unless typed?(values)

        new(**values)
      end
      private_class_method :parse

      def self.typed?(values)
        [ :snapshot, :cms_version ].all? { |m| values[m].nil? || values[m].is_a?(String) } &&
          [ :database_bytes, :files_bytes ].all? { |m| values[m].nil? || values[m].is_a?(Integer) } &&
          (values[:duration_seconds].nil? || values[:duration_seconds].is_a?(Numeric))
      end
      private_class_method :typed?

      # mkdir -p, a temp file beside the file, a rename: whole or absent.
      def write(path)
        path = Pathname(path)
        FileUtils.mkdir_p(path.dirname)
        temp = Pathname("#{path}.tmp#{Process.pid}")
        begin
          temp.write(JSON.pretty_generate(to_json_hash))
          temp.chmod(0o644)
          File.rename(temp, path)
        ensure
          FileUtils.rm_f(temp)
        end
      end

      def ok? = outcome == "ok"
      def unreadable? = outcome == "unreadable"
      def check_failed? = last_check_outcome == "failed"
      def total_bytes = database_bytes.to_i + files_bytes.to_i
      def good_backup_age(now) = age_since(last_ok_at, now)
      def since_first_run(now) = age_since(first_run_at, now)

      private

      def age_since(time, now) = time && [ now - time, 0.0 ].max.to_f

      def to_json_hash
        to_h.transform_values { |v| v.is_a?(Time) ? v.utc.iso8601 : v }.transform_keys(&:to_s)
      end
    end
  end
end
