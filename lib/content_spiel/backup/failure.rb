module ContentSpiel
  class Backup
    # Why a run failed, as one of five fixed reasons. A tool's own message
    # (restic's, pg_dump's) is read here and never printed or stored: it can
    # name a host, a bucket or a user. A repository that does not exist yet
    # (restic exit 10) is destination_unreachable; its sentence says "or holds
    # no repository yet", so no sixth reason exists.
    module Failure
      REASONS = %w[destination_unreachable wrong_password database_unreachable disk_full other].freeze

      DISK_FULL = /No space left on device/i
      RESTIC_WRONG_PASSWORD = /wrong password or no key found/i
      RESTIC_DESTINATION = Regexp.union(
        "dial tcp", "no such host", "connection refused", "i/o timeout", "Access Denied",
        "InvalidAccessKeyId", "SignatureDoesNotMatch", "NoSuchBucket", "unable to open config file"
      ).then { |union| Regexp.new(union.source, Regexp::IGNORECASE) }
      PG_DUMP_DATABASE = Regexp.union(
        "could not connect", "connection to server", "could not translate host name",
        "password authentication failed", "no password supplied"
      ).then { |union| Regexp.new(union.source, Regexp::IGNORECASE) }

      # tool is :restic or :pg_dump.
      def self.classify(tool:, exit_status:, stderr:)
        return "disk_full" if stderr.match?(DISK_FULL)

        case tool
        when :restic
          return "wrong_password" if exit_status == 12 || stderr.match?(RESTIC_WRONG_PASSWORD)
          return "destination_unreachable" if exit_status == 10 || stderr.match?(RESTIC_DESTINATION)
        when :pg_dump
          return "database_unreachable" if stderr.match?(PG_DUMP_DATABASE)
        end
        "other"
      end
    end
  end
end
