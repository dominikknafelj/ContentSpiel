require "json"
require "fileutils"
require_relative "version"
require_relative "backup/failure"
require_relative "backup/status"
require_relative "backup/running_version"
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
  #   Then the status file, ok or failed, which with RunningVersion's file
  #   beside it is all it writes in the files volume. A run whose snapshot
  #   was taken and whose forget then failed is failed, but records that
  #   snapshot as the newest good backup. One run at a time: a run holds a
  #   lock on DUMP_DIR + LOCK_SUFFIX (on the container's own disk), and a
  #   run that finds it held says so and ends with 1, writing no status, so a
  #   person's `kamal accessory exec backup --reuse "bin/backup run"` and the
  #   schedule's never share the dump or the status.
  # - schedule: run every BACKUP_EVERY hours (default 24) at the fixed UTC
  #   hours BACKUP_HOUR + k * BACKUP_EVERY, its slots, the accessory's
  #   long-running command. Configured, it first writes its version and its
  #   cadence (RunningVersion), which System status and the alert read. It
  #   sleeps until the next slot, runs, and sleeps until the one after:
  #   a failed run is not retried, so a broken destination fails once a slot,
  #   never in a loop. Unconfigured, it says so once a day and runs nothing.
  #   stop! (bin/backup traps TERM and INT with it: as the container's PID 1,
  #   Ruby would otherwise ignore TERM and Kamal's stop would wait and kill)
  #   wakes a sleep, which ends the schedule with 0, or sends TERM to the
  #   running tool, which ends the run as failed ("other") and the schedule
  #   with 143. A status file that cannot be written (a full disk) raises out
  #   of the schedule; the accessory's restart policy (Kamal's default,
  #   unless-stopped) starts it again, sleeping until the next slot.
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
  # that is /dev/null.
  class Backup
    COMMANDS = %w[run schedule list restore init].freeze
    DATABASE = "content_spiel_production"
    DUMP_DIR = "/tmp/content_spiel_backup"
    DUMP_FILE = "database.dump"
    # The run lock's file, beside the dump folder and never in it (restic
    # backs that folder up) nor in the files volume.
    LOCK_SUFFIX = ".lock"
    # Every snapshot of the last day (restic 0.14 and later; the image's is
    # Debian's 0.18), then one a day, a week and a month: at a cadence of a
    # day the first rule keeps nothing the second would not.
    RETENTION = %w[--keep-within-hourly 24h --keep-daily 7 --keep-weekly 4 --keep-monthly 6].freeze
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
        schedule               a backup every BACKUP_EVERY hours (default 24) from BACKUP_HOUR (UTC, default 3)
        list                   the snapshots
        restore SNAPSHOT DIR   a snapshot (or latest) into an empty folder DIR, as database.dump and files/
        init                   a new repository at BACKUP_REPOSITORY, once per site
    TEXT
    UNITS = %w[B KB MB GB TB].freeze
    DEFAULT_HOUR = 3
    DAY = 86_400
    HOUR = 3_600
    # The hours BACKUP_EVERY may name: the divisors of a day, so the slots
    # fall at the same UTC hours every day. RunningVersion holds the list, so
    # the web container reads a cadence by the same one.
    EVERY_HOURS = RunningVersion::EVERY_HOURS
    DEFAULT_EVERY = RunningVersion::DEFAULT_EVERY
    # The exit code of a schedule stopped during a run: 128 + TERM.
    STOPPED = 143

    # A step that failed, with its reason (one of Failure::REASONS).
    class StepFailed < StandardError
      attr_reader :step, :reason

      def initialize(step, reason)
        @step = step
        @reason = reason
        super("#{step}: #{reason}")
      end
    end

    # The next slot strictly after now: the first of the UTC hours
    # hour + k * every (mod 24), on the hour. `every` divides 24, so the
    # slots repeat each day and counting from the day's first is enough.
    def self.next_run_at(now, hour, every = DEFAULT_EVERY)
      now = now.getutc
      first = Time.utc(now.year, now.month, now.day, hour % every)
      return first if first > now

      first + (((now - first) / (every * HOUR)).floor + 1) * every * HOUR
    end

    # Whether the web container is told the site keeps no backups on purpose
    # (BACKUPS=off, any case): System status shows the row as off and the
    # alert stays quiet. Any other value, or none, expects backups, so a
    # misspelt switch keeps the warning. The one reader of the variable.
    def self.off?(env = ENV)
      env["BACKUPS"].to_s.strip.casecmp?("off")
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

    # sleeper: nil sleeps until the seconds pass or stop! is called.
    def initialize(env:, out:, err:, root:, runner: Runner.new, clock: -> { Time.now.utc },
      sleeper: nil, dump_dir: DUMP_DIR)
      @env = env
      @out = out
      @err = err
      @root = File.expand_path(root)
      @runner = runner
      @clock = clock
      @sleeper = sleeper || method(:wait)
      @dump_dir = File.expand_path(dump_dir)
      # A pipe and not a Queue: stop! runs in a signal trap on the thread
      # that sleeps, and Queue#pop(timeout:) does not wake for a push made
      # there (Ruby 3.4) until its timeout, where IO.select does.
      @wake_read, @wake_write = IO.pipe
      @stopping = false

      # A value that is not secret is read stripped; a secret is used as given.
      @repository = plain(@env["BACKUP_REPOSITORY"])
      @site = plain(@env["BACKUP_SITE"]) || DEFAULT_SITE
      @restic_password = present(@env["RESTIC_PASSWORD"])
      @aws_access_key_id = present(@env["AWS_ACCESS_KEY_ID"])
      @aws_secret_access_key = present(@env["AWS_SECRET_ACCESS_KEY"])
      @aws_default_region = plain(@env["AWS_DEFAULT_REGION"])
      @pghost = plain(@env["PGHOST"])
      @pguser = plain(@env["PGUSER"]) || DEFAULT_PGUSER
      @postgres_password = present(@env["POSTGRES_PASSWORD"])
      @home = present(@env["HOME"])
      @backup_hour = @env["BACKUP_HOUR"]&.strip
      @backup_every = @env["BACKUP_EVERY"]&.strip
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

    # Runs `runs` slots (tests give a number), and answers 0, or STOPPED when
    # stop! came during a run, or 1 for a BACKUP_HOUR or BACKUP_EVERY it
    # refuses.
    def schedule(runs: Float::INFINITY)
      hour = backup_hour or return 1
      every = backup_every or return 1
      write_running_version(every) if @repository
      done = 0
      last_run = nil
      until @stopping || done >= runs
        if @repository
          # From the later of now and the last run's slot: a wall clock set
          # back after a run cannot give a second run in that slot.
          next_run = self.class.next_run_at([ @clock.call, last_run ].compact.max, hour, every)
          last_run = next_run
          @out.puts("[backup] next run at #{next_run.strftime("%Y-%m-%d %H:%M")} UTC")
          @sleeper.call(next_run - @clock.call)
          break if @stopping

          run
          return STOPPED if @stopping
        else
          @out.puts(NOT_CONFIGURED)
          @sleeper.call(DAY) if done + 1 < runs
        end
        done += 1
      end
      0
    end

    # From a signal trap: no Mutex, nothing that waits. Wakes the sleep, and
    # sends TERM to a running tool (the runner does nothing with none).
    def stop!
      @stopping = true
      @wake_write.write_nonblock(".", exception: false)
      @runner.interrupt
    end

    def run
      unless @repository
        @out.puts(NOT_CONFIGURED)
        return 0
      end

      with_run_lock { locked_run }
    end

    private

    # The run's own steps, under the run lock.
    def locked_run
      started = @clock.call
      previous = Status.read(Status.path(@root))
      previous = nil if previous&.unreadable?

      missing = missing_variables("run")
      return failed(previous, started, missing.first.last) unless missing.empty?

      taken = {}
      begin
        take(previous, taken)
      rescue StepFailed => failure
        @out.puts("[backup] failed at #{failure.step}: #{failure.reason}")
        return failed(previous, started, failure.reason, taken)
      end

      finished = @clock.call
      Status.new(finished_at: finished, outcome: "ok", **taken,
        duration_seconds: (finished - started).round, first_run_at: previous&.first_run_at || finished,
        last_ok_at: finished, error: nil, cms_version: ContentSpiel::VERSION).write(Status.path(@root))
      @out.puts("[backup] finished in #{(finished - started).round}s: snapshot #{taken[:snapshot]}")
      0
    end

    # A non-blocking flock on the lock file, released when the block ends
    # (the file stays: removing it would let a waiting run lock a file no
    # longer at the path). Held by another run: one line on err and 1.
    def with_run_lock
      File.open("#{@dump_dir}#{LOCK_SUFFIX}", File::RDWR | File::CREAT, 0o600) do |lock|
        unless lock.flock(File::LOCK_EX | File::LOCK_NB)
          @err.puts("[backup] another backup is already running")
          return 1
        end
        yield
      end
    end

    # The version marker is a hint for System status, so a write that fails
    # is named by its class and the schedule goes on: System status then
    # compares the status file's version.
    def write_running_version(every)
      RunningVersion.new(cms_version: ContentSpiel::VERSION, started_at: @clock.call, every_hours: every)
        .write(RunningVersion.path(@root))
    rescue SystemCallError => error
      @err.puts("[backup] could not write the accessory's version: #{error.class}")
    end

    def present(value) = value.to_s.strip.empty? ? nil : value

    def plain(value) = present(value)&.strip

    def wait(seconds)
      IO.select([ @wake_read ], nil, nil, [ seconds, 0 ].max)
    end

    # BACKUP_HOUR as an Integer (DEFAULT_HOUR when unset), or nil with the
    # sentence said.
    def backup_hour
      return DEFAULT_HOUR if @backup_hour.nil?
      return @backup_hour.to_i if @backup_hour.match?(/\A\d{1,2}\z/) && @backup_hour.to_i <= 23

      @err.puts("Cannot schedule: BACKUP_HOUR must be a whole hour from 0 to 23 (UTC), or unset for #{DEFAULT_HOUR}.")
      nil
    end

    # BACKUP_EVERY as an Integer (DEFAULT_EVERY when unset or blank), or nil
    # with the sentence said.
    def backup_every
      return DEFAULT_EVERY if @backup_every.nil? || @backup_every.empty?
      return @backup_every.to_i if @backup_every.match?(/\A\d{1,2}\z/) && EVERY_HOURS.include?(@backup_every.to_i)

      @err.puts("Cannot schedule: BACKUP_EVERY must be one of #{EVERY_HOURS.join(", ")} (hours), or unset for #{DEFAULT_EVERY}.")
      nil
    end

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
    # whatever happens. Fills `taken` with the status's fields the run
    # measured: the snapshot and its sizes once the backup step succeeded,
    # so a later failure still records them.
    def take(previous, taken)
      dump_path = File.join(@dump_dir, DUMP_FILE)
      database_bytes = step("dump") { dump(dump_path) }
      step("backup") do
        snapshot, processed = send_snapshot
        taken.merge!(snapshot: snapshot[0, 8], database_bytes: database_bytes,
          files_bytes: [ processed - database_bytes, 0 ].max)
        processed
      end
      step("forget") do
        restic("forget", NICE + %W[restic forget --host #{@site}] + RETENTION + %w[--prune])
        nil
      end
      taken.merge!(check(previous))
    ensure
      FileUtils.rm_f(dump_path)
    end

    # Prints the step's start and end (with the size the block answers, if
    # any) and answers that size. Anything a step raises that is not a
    # StepFailed (a tool that cannot be started) is the reason "other", named
    # on err by its class alone.
    #
    # After stop!, a step that has not started does not start, and one that
    # was running fails as "other", whatever its tool answered: a tool killed
    # by TERM can print anything, and its words are no reason.
    def step(name)
      raise StepFailed.new(name, "other") if @stopping

      @out.puts("[backup] #{name} started")
      began = @clock.call
      size = begin
        yield
      rescue StepFailed => failure
        raise(@stopping ? StepFailed.new(name, "other") : failure)
      rescue StandardError => error
        @err.puts("[backup] #{name} stopped by #{error.class}")
        raise StepFailed.new(name, "other")
      end
      raise StepFailed.new(name, "other") if @stopping

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
    # when not. A failed check leaves the backup ok; a check that stop! ended
    # is no verdict on the data, so it ends the run as a stop does and the
    # check stays due.
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
        raise if @stopping

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
    # sizes, so a failure never hides how old the newest good backup is.
    # That is this run's snapshot when it was taken before the failure
    # (`taken`), and the previous status's otherwise.
    def failed(previous, started, reason, taken = {})
      finished = @clock.call
      newest = if taken[:snapshot]
        taken.slice(:snapshot, :database_bytes, :files_bytes).merge(last_ok_at: finished)
      else
        { snapshot: previous&.snapshot, database_bytes: previous&.database_bytes,
          files_bytes: previous&.files_bytes, last_ok_at: previous&.last_ok_at }
      end
      Status.new(finished_at: finished, outcome: "failed", **newest,
        duration_seconds: (finished - started).round, first_run_at: previous&.first_run_at || finished,
        last_check_at: previous&.last_check_at,
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
      secrets = [ @restic_password, @aws_access_key_id, @aws_secret_access_key, @postgres_password,
        @repository, @repository&.sub(%r{/+\z}, "") ]
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
