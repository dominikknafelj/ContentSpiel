require "json"
require "fileutils"
require_relative "version"
require_relative "backup/failure"
require_relative "backup/status"
require_relative "backup/runner"

module ContentSpiel
  # The backup accessory's command, bin/backup (docs/reference/backups.md).
  # Plain Ruby, standard library only: the accessory does not boot Rails.
  #
  # - run: pg_dump of the primary database into DUMP_DIR (the container's own
  #   disk, never the files volume), one restic snapshot of that folder and of
  #   <root>/storage (the status folder excluded), restic forget with
  #   RETENTION, and once a month (the first run of a month, or the run after
  #   a failed check) restic check of one twelfth of the data, the month's.
  #   Then the status file, ok or failed, which is the one thing it writes in
  #   the files volume.
  # - schedule: run once a day at BACKUP_HOUR.
  # - list: restic's snapshots. init: a new repository. restore: a snapshot's
  #   dump and files into an empty folder, as database.dump and files/; it
  #   touches no database and no live volume.
  #
  # Every snapshot is taken with --host BACKUP_SITE and the same two absolute
  # paths, and forget narrows to that host: restic groups snapshots by host
  # and paths, so a container's random hostname or a random dump folder would
  # make each snapshot a group of its own, which forget keeps whole, and the
  # bucket would grow forever.
  #
  # A run's tools start under nice and ionice's idle class (-t: a host that
  # refuses the class runs them anyway), so a backup yields the CPU and the
  # disk to the website on the same server.
  #
  # Never a tool's message: restic and pg_dump can print a password, a key or
  # the repository's address. run prints its own lines only and records a
  # failure as one of Failure::REASONS; list and init pass restic's stdout
  # through with every secret and the repository replaced by HIDDEN, and drop
  # its stderr. A missing secret is named (its name, never a value) before any
  # tool starts, since a tool without its password would prompt on a stdin
  # that is not there.
  class Backup
    COMMANDS = %w[run schedule list restore init].freeze
    DATABASE = "content_spiel_production"
    DUMP_DIR = "/tmp/content_spiel_backup"
    DUMP_FILE = "database.dump"
    RETENTION = %w[--keep-daily 7 --keep-weekly 4 --keep-monthly 6].freeze
    CHECK_PARTS = 12
    NICE = %w[nice -n 19 ionice -c 3 -t].freeze
    # The children's PATH, fixed: the image's tools are all here, and the
    # accessory's own PATH is not handed on.
    PATH = "/usr/local/bin:/usr/bin:/bin"
    DEFAULT_SITE = "contentspiel"
    DEFAULT_PGUSER = "postgres"
    HIDDEN = "[hidden]"
    NOT_CONFIGURED = "Backups are not configured: BACKUP_REPOSITORY is not set."
    USAGE = <<~TEXT
      Usage: bin/backup COMMAND
        run                    one backup now
        schedule               a backup every day at BACKUP_HOUR (UTC, default 3)
        list                   the snapshots
        restore SNAPSHOT DIR   a snapshot (or latest) into an empty folder DIR, as database.dump and files/
        init                   a new repository at BACKUP_REPOSITORY, once per site
    TEXT
    UNITS = %w[B KB MB GB TB].freeze

    # A step that failed, with its reason (one of Failure::REASONS).
    class StepFailed < StandardError
      attr_reader :step, :reason

      def initialize(step, reason)
        @step = step
        @reason = reason
        super("#{step}: #{reason}")
      end
    end

    def self.human_size(bytes)
      size = bytes.to_f
      unit = 0
      while size >= 1000 && unit < UNITS.size - 1
        size /= 1000
        unit += 1
      end
      unit.zero? ? "#{bytes} B" : format("%.1f %s", size, UNITS[unit])
    end

    def initialize(env:, out:, err:, root:, runner: Runner.new, clock: -> { Time.now.utc },
      sleeper: ->(seconds) { sleep(seconds) }, dump_dir: DUMP_DIR)
      @env = env
      @out = out
      @err = err
      @root = File.expand_path(root)
      @runner = runner
      @clock = clock
      @sleeper = sleeper
      @dump_dir = File.expand_path(dump_dir)

      @repository = present(@env["BACKUP_REPOSITORY"])
      @site = present(@env["BACKUP_SITE"]) || DEFAULT_SITE
      @restic_password = present(@env["RESTIC_PASSWORD"])
      @aws_access_key_id = present(@env["AWS_ACCESS_KEY_ID"])
      @aws_secret_access_key = present(@env["AWS_SECRET_ACCESS_KEY"])
      @aws_default_region = present(@env["AWS_DEFAULT_REGION"])
      @pghost = present(@env["PGHOST"])
      @pguser = present(@env["PGUSER"]) || DEFAULT_PGUSER
      @postgres_password = present(@env["POSTGRES_PASSWORD"])
      @home = present(@env["HOME"])
    end

    # The exit code: 0, 1 for a failure, 2 for a command line it does not know.
    def call(argv)
      command, *args = argv
      case [ command, args.size ]
      in [ "run", 0 ] then run
      in [ "schedule", 0 ] then schedule
      in [ "list", 0 ] then passthrough("list", %w[restic snapshots])
      in [ "init", 0 ] then passthrough("init", %w[restic init])
      in [ "restore", 2 ] then restore(*args)
      else
        @err.print(USAGE)
        2
      end
    end

    def run
      unless @repository
        @out.puts(NOT_CONFIGURED)
        return 0
      end

      started = @clock.call
      previous = Status.read(Status.path(@root))
      previous = nil if previous&.unreadable?

      missing = missing_variables("run")
      return failed(previous, started, missing.first.last) unless missing.empty?

      begin
        taken = take(previous)
      rescue StepFailed => failure
        @out.puts("[backup] failed at #{failure.step}: #{failure.reason}")
        return failed(previous, started, failure.reason)
      end

      finished = @clock.call
      Status.new(finished_at: finished, outcome: "ok", **taken,
        duration_seconds: (finished - started).round, first_run_at: previous&.first_run_at || finished,
        last_ok_at: finished, error: nil, cms_version: ContentSpiel::VERSION).write(Status.path(@root))
      @out.puts("[backup] finished in #{(finished - started).round}s: snapshot #{taken[:snapshot]}")
      0
    end

    private

    def present(value) = value.to_s.strip.empty? ? nil : value

    def s3? = @repository.to_s.start_with?("s3:")

    # [name, reason] of every variable the command needs and lacks, in the
    # order a run needs them, with one sentence naming them on err.
    def missing_variables(command)
      needed = []
      needed << [ "POSTGRES_PASSWORD", @postgres_password, "database_unreachable" ] if command == "run"
      needed << [ "RESTIC_PASSWORD", @restic_password, "wrong_password" ]
      if s3?
        needed << [ "AWS_ACCESS_KEY_ID", @aws_access_key_id, "destination_unreachable" ]
        needed << [ "AWS_SECRET_ACCESS_KEY", @aws_secret_access_key, "destination_unreachable" ]
      end
      missing = needed.select { |_, value, _| value.nil? }.map { |name, _, reason| [ name, reason ] }
      unless missing.empty?
        names = missing.map(&:first)
        listed = names.one? ? "#{names.first} is" : "#{names[0..-2].join(", ")} and #{names.last} are"
        @err.puts("Cannot #{command}: #{listed} not set.")
      end
      missing
    end

    # Unconfigured, or without a secret: false, with the sentence said.
    def ready?(command)
      unless @repository
        @err.puts(NOT_CONFIGURED)
        return false
      end
      missing_variables(command).empty?
    end

    # The steps of a run, each raising StepFailed; the dump is removed
    # whatever happens. Answers the status's fields the run measured.
    def take(previous)
      dump_path = File.join(@dump_dir, DUMP_FILE)
      database_bytes = step("dump") { dump(dump_path) }
      snapshot = processed = nil
      step("backup") do
        snapshot, processed = send_snapshot
        processed
      end
      step("forget") do
        restic("forget", NICE + %W[restic forget --host #{@site}] + RETENTION + %w[--prune])
        nil
      end
      { snapshot: snapshot[0, 8], database_bytes: database_bytes,
        files_bytes: [ processed - database_bytes, 0 ].max, **check(previous) }
    ensure
      FileUtils.rm_f(dump_path)
    end

    # Prints the step's start and end (with the size the block answers, if
    # any) and answers that size. Anything a step raises that is not a
    # StepFailed (a tool that cannot be started) is the reason "other", named
    # on err by its class alone.
    def step(name)
      @out.puts("[backup] #{name} started")
      began = @clock.call
      size = begin
        yield
      rescue StepFailed
        raise
      rescue StandardError => error
        @err.puts("[backup] #{name} stopped by #{error.class}")
        raise StepFailed.new(name, "other")
      end
      @out.puts("[backup] #{name} finished in #{(@clock.call - began).round}s#{", #{self.class.human_size(size)}" if size}")
      size
    end

    def dump(path)
      FileUtils.mkdir_p(@dump_dir, mode: 0o700)
      argv = NICE + %W[pg_dump --format=custom --no-password --file #{path} --dbname #{DATABASE}]
      child_env = { "PATH" => PATH, "PGHOST" => @pghost, "PGUSER" => @pguser, "PGPASSWORD" => @postgres_password }.compact
      outcome = @runner.call(argv, env: child_env)
      unless outcome.exit_status.zero?
        raise StepFailed.new("dump", Failure.classify(tool: :pg_dump, exit_status: outcome.exit_status, stderr: outcome.stderr))
      end
      File.size(path)
    end

    # [snapshot id, bytes processed] from restic's --json summary line.
    def send_snapshot
      outcome = restic("backup", NICE + %W[restic backup --json --host #{@site} --tag site=#{@site}
        --tag cms=#{ContentSpiel::VERSION} --exclude #{Status.path(@root).dirname} #{@dump_dir} #{File.join(@root, "storage")}])
      summary = outcome.stdout.scrub.each_line.filter_map { |line| parse_json(line) }
        .find { |message| message.is_a?(Hash) && message["message_type"] == "summary" }
      id, processed = summary&.values_at("snapshot_id", "total_bytes_processed")
      raise StepFailed.new("backup", "other") unless id.is_a?(String) && processed.is_a?(Integer)

      [ id, processed ]
    end

    def parse_json(line)
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end

    # The month's check when due, its fields carried from the previous status
    # when not. A failed check leaves the backup ok.
    def check(previous)
      now = @clock.call
      unless check_due?(previous, now)
        return { last_check_at: previous.last_check_at, last_check_outcome: previous.last_check_outcome,
                 check_error: previous.check_error }
      end

      begin
        step("check") do
          restic("check", NICE + %W[restic check --read-data-subset=#{now.month}/#{CHECK_PARTS}])
          nil
        end
        { last_check_at: now, last_check_outcome: "ok", check_error: nil }
      rescue StepFailed => failure
        @out.puts("[backup] check failed: #{failure.reason}")
        { last_check_at: now, last_check_outcome: "failed", check_error: failure.reason }
      end
    end

    def check_due?(previous, now)
      last = previous&.last_check_at
      last.nil? || previous.check_failed? || [ last.year, last.month ] != [ now.year, now.month ]
    end

    def restic(name, argv)
      outcome = @runner.call(argv, env: restic_env)
      return outcome if outcome.exit_status.zero?

      raise StepFailed.new(name, Failure.classify(tool: :restic, exit_status: outcome.exit_status, stderr: outcome.stderr))
    end

    def restic_env
      { "PATH" => PATH, "HOME" => @home, "RESTIC_REPOSITORY" => @repository, "RESTIC_PASSWORD" => @restic_password,
        "AWS_ACCESS_KEY_ID" => @aws_access_key_id, "AWS_SECRET_ACCESS_KEY" => @aws_secret_access_key,
        "AWS_DEFAULT_REGION" => @aws_default_region }.compact
    end

    # A failed run's status: the newest good backup's time, snapshot and
    # sizes kept from the previous status, so a failure never hides how old
    # the newest good backup is.
    def failed(previous, started, reason)
      finished = @clock.call
      Status.new(finished_at: finished, outcome: "failed", snapshot: previous&.snapshot,
        database_bytes: previous&.database_bytes, files_bytes: previous&.files_bytes,
        duration_seconds: (finished - started).round, first_run_at: previous&.first_run_at || finished,
        last_ok_at: previous&.last_ok_at, last_check_at: previous&.last_check_at,
        last_check_outcome: previous&.last_check_outcome, check_error: previous&.check_error,
        error: reason, cms_version: ContentSpiel::VERSION).write(Status.path(@root))
      1
    end

    # list and init: restic's stdout with the secrets hidden; its stderr
    # never, a failure said as its reason.
    def passthrough(command, argv)
      return 1 unless ready?(command)

      outcome = restic(command, argv)
      @out.print(hide(outcome.stdout))
      0
    rescue StepFailed => failure
      @err.puts("[backup] #{command} failed: #{failure.reason}")
      1
    rescue SystemCallError => error
      @err.puts("[backup] #{command} stopped by #{error.class}")
      1
    end

    def hide(text)
      secrets = [ @restic_password, @aws_access_key_id, @aws_secret_access_key, @postgres_password, @repository ]
        .compact.uniq.sort_by { |value| -value.size }
      secrets.reduce(text.scrub) { |shown, secret| shown.gsub(secret, HIDDEN) }
    end

    # Into DIR/.restic first, then the dump and the files volume moved up to
    # DIR/database.dump and DIR/files, so DIR holds the two and nothing else.
    def restore(snapshot, dir)
      return 1 unless ready?("restore")

      target = File.expand_path(dir)
      if File.exist?(target) && !(File.directory?(target) && Dir.empty?(target))
        @err.puts("#{target} is not empty: restore into an empty or new folder.")
        return 1
      end

      FileUtils.mkdir_p(target)
      staging = File.join(target, ".restic")
      begin
        @out.puts("[backup] restore started")
        restic("restore", %W[restic restore #{snapshot} --host #{@site} --target #{staging}])
        dump = File.join(staging, @dump_dir, DUMP_FILE)
        files = File.join(staging, @root, "storage")
        raise StepFailed.new("restore", "other") unless File.file?(dump) && File.directory?(files)

        File.rename(dump, File.join(target, DUMP_FILE))
        File.rename(files, File.join(target, "files"))
      rescue StepFailed => failure
        @err.puts("[backup] restore failed: #{failure.reason}")
        return 1
      rescue SystemCallError => error
        @err.puts("[backup] restore stopped by #{error.class}")
        return 1
      ensure
        FileUtils.rm_rf(staging)
      end
      @out.puts("Restored snapshot #{snapshot} into #{target}: #{DUMP_FILE} and files/. Nothing else was changed.")
      0
    end
  end
end
