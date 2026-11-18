require "test_helper"
require "tmpdir"
require "stringio"
require_relative "../../support/fake_backup_runner"

class ContentSpiel::BackupTest < ActiveSupport::TestCase
  Backup = ContentSpiel::Backup
  Status = Backup::Status
  Runner = Backup::Runner
  Outcome = Runner::Outcome

  SECRETS = { "RESTIC_PASSWORD" => "restic-secret-1", "AWS_ACCESS_KEY_ID" => "key-id-2",
              "AWS_SECRET_ACCESS_KEY" => "key-secret-3", "POSTGRES_PASSWORD" => "pg-secret-4" }.freeze
  REPOSITORY = "s3:https://s3.example.com/bucket/site".freeze
  HIDDEN = SECRETS.values + [ REPOSITORY ]
  NICE = FakeBackupRunner::PREFIX
  NOW = Time.utc(2026, 11, 18, 3, 0, 0)
  SITE = "example-site".freeze

  setup do
    @root = Pathname(Dir.mktmpdir)
    @dump_dir = Pathname(Dir.mktmpdir)
    @root.join("storage", "ab", "cd").mkpath
    @root.join("storage", "ab", "cd", "abcd1234").write("an image")
    @out = StringIO.new
    @err = StringIO.new
    @runner = FakeBackupRunner.new
    @env = { "BACKUP_REPOSITORY" => REPOSITORY, "BACKUP_SITE" => SITE, "PGHOST" => "db",
             "HOME" => "/home/backup", "AWS_DEFAULT_REGION" => "auto" }.merge(SECRETS)
  end

  teardown do
    FileUtils.remove_entry(@root)
    FileUtils.remove_entry(@dump_dir) if @dump_dir.exist?
  end

  def backup(env: @env, clock: -> { NOW }, runner: @runner, sleeper: ->(_) { flunk "nothing sleeps here" })
    Backup.new(env: env, out: @out, err: @err, root: @root.to_s, runner: runner, clock: clock,
      sleeper: sleeper, dump_dir: @dump_dir.to_s)
  end

  # A clock that each sleep moves on, and the sleeps it was asked for.
  def fake_time(start)
    now = start
    sleeps = []
    [ -> { now }, ->(seconds) { sleeps << seconds; now += seconds }, sleeps ]
  end

  def status = Status.read(Status.path(@root))

  def dump_file = @dump_dir.join(Backup::DUMP_FILE).to_s

  def storage = @root.join("storage").to_s

  def expected_argv
    [
      NICE + %W[pg_dump --format=custom --no-password --file #{dump_file} --dbname content_spiel_production],
      NICE + %W[restic backup --json --host #{SITE} --tag site=#{SITE} --tag cms=#{ContentSpiel::VERSION}
                --exclude #{@root.join("storage", "backup")} #{@dump_dir} #{storage}],
      NICE + %W[restic forget --host #{SITE} --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune]
    ]
  end

  def previous_ok(**over)
    Status.new(finished_at: Time.utc(2026, 11, 17, 3), outcome: "ok", snapshot: "99887766",
      database_bytes: 500, files_bytes: 7_000, duration_seconds: 30, first_run_at: Time.utc(2026, 10, 1, 3),
      last_ok_at: Time.utc(2026, 11, 17, 3), last_check_at: Time.utc(2026, 11, 1, 3),
      last_check_outcome: "ok", check_error: nil, error: nil, cms_version: "0.10.0", **over)
  end

  def tree(dir)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).reject { |p| p.end_with?(".") }.sort.to_h do |path|
      full = File.join(dir, path)
      [ path, File.directory?(full) ? :dir : [ File.size(full), File.mtime(full) ] ]
    end
  end

  test "the constants are the command's fixed values" do
    assert_equal %w[run schedule list restore init], Backup::COMMANDS
    assert_equal "content_spiel_production", Backup::DATABASE
    assert_equal "/tmp/content_spiel_backup", Backup::DUMP_DIR
    assert_equal "database.dump", Backup::DUMP_FILE
    assert_equal %w[--keep-daily 7 --keep-weekly 4 --keep-monthly 6], Backup::RETENTION
    assert_equal 12, Backup::CHECK_PARTS
  end

  test "without BACKUP_REPOSITORY, run says backups are not configured, exits 0 and writes no status" do
    assert_equal 0, backup(env: @env.except("BACKUP_REPOSITORY")).call([ "run" ])
    assert_equal "Backups are not configured: BACKUP_REPOSITORY is not set.\n", @out.string
    assert_empty @runner.calls
    assert_nil status

    assert_equal 0, backup(env: @env.merge("BACKUP_REPOSITORY" => "  ")).call([ "run" ])
    assert_empty @runner.calls
  end

  test "a run dumps, backs up, forgets, writes an ok status and removes the dump" do
    previous_ok.write(Status.path(@root))
    ticks = []
    clock = -> { (NOW + ticks.size * 2).tap { |time| ticks << time } }

    assert_equal 0, backup(clock: clock).call([ "run" ])

    assert_equal expected_argv, @runner.calls.map(&:first)
    written = status
    assert_equal "ok", written.outcome
    assert_equal "1a2b3c4d", written.snapshot
    assert_equal 1_234, written.database_bytes
    assert_equal 100_000, written.files_bytes
    assert_equal ticks.last, written.finished_at
    assert_equal (ticks.last - ticks.first).round, written.duration_seconds
    assert_equal ticks.last, written.last_ok_at
    assert_equal Time.utc(2026, 10, 1, 3), written.first_run_at
    assert_equal ContentSpiel::VERSION, written.cms_version
    assert_nil written.error
    assert_empty Dir.children(@dump_dir)

    lines = @out.string.lines(chomp: true)
    assert_equal [ "[backup] dump started", "[backup] dump finished in 2s, 1.2 KB",
      "[backup] backup started", "[backup] backup finished in 2s, 101.2 KB",
      "[backup] forget started", "[backup] forget finished in 2s" ], lines.first(6)
    assert_match(/\A\[backup\] finished in \d+s: snapshot 1a2b3c4d\z/, lines.last)
    assert_empty @err.string
  end

  test "a first run sets first_run_at and last_ok_at to its finish, and files_bytes never goes below zero" do
    runner = FakeBackupRunner.new(dump_bytes: 5_000, processed_bytes: 4_000)
    assert_equal 0, backup(runner: runner).call([ "run" ])
    assert_equal NOW, status.first_run_at
    assert_equal NOW, status.last_ok_at
    assert_equal 0, status.files_bytes
  end

  test "an unreadable previous status counts as none" do
    Status.path(@root).dirname.mkpath
    Status.path(@root).write("not json")
    assert_equal 0, backup.call([ "run" ])
    assert_equal NOW, status.first_run_at
  end

  test "every snapshot is taken with the site as its host and the same two paths, and forget narrows to that host" do
    backup(clock: -> { NOW }).call([ "run" ])
    backup(clock: -> { NOW + 86_400 }).call([ "run" ])

    backups = @runner.calls.map(&:first).select { |argv| FakeBackupRunner.step(argv) == "backup" }
    assert_equal 2, backups.size
    assert_equal backups.first, backups.last
    bare = FakeBackupRunner.bare(backups.first)
    assert_equal [ "--host", SITE ], bare[bare.index("--host"), 2]
    assert_equal [ @dump_dir.to_s, storage ], bare.last(2)

    forgets = @runner.calls.map(&:first).select { |argv| FakeBackupRunner.step(argv) == "forget" }
    forgets.each { |argv| assert_equal [ "--host", SITE ], FakeBackupRunner.bare(argv)[2, 2] }
  end

  test "the site's name defaults to contentspiel" do
    backup(env: @env.except("BACKUP_SITE")).call([ "run" ])
    argv = FakeBackupRunner.bare(@runner.call_for("backup").first)
    assert_equal [ "--host", "contentspiel" ], argv[argv.index("--host"), 2]
    assert_includes argv, "site=contentspiel"
  end

  test "the monthly check runs on the first run of a month, and again after a failed check" do
    december = Time.utc(2026, 12, 1, 3)
    previous_ok.write(Status.path(@root))

    assert_equal 0, backup(clock: -> { december }).call([ "run" ])
    assert_equal NICE + %w[restic check --read-data-subset=12/12], @runner.calls.last.first
    assert_equal december, status.last_check_at
    assert_equal "ok", status.last_check_outcome
    assert_includes @out.string, "[backup] check finished in 0s"

    runner = FakeBackupRunner.new
    backup(clock: -> { december + 3_600 }, runner: runner).call([ "run" ])
    assert_equal %w[pg_dump backup forget], runner.steps
    assert_equal december, status.last_check_at

    previous_ok(last_check_at: december, last_check_outcome: "failed", check_error: "other").write(Status.path(@root))
    runner = FakeBackupRunner.new
    backup(clock: -> { december + 7_200 }, runner: runner).call([ "run" ])
    assert_equal %w[pg_dump backup forget check], runner.steps
    assert_equal "ok", status.last_check_outcome
    assert_nil status.check_error
  end

  test "a first run of all checks the repository" do
    backup.call([ "run" ])
    assert_equal %w[pg_dump backup forget check], @runner.steps
    assert_equal NICE + %w[restic check --read-data-subset=11/12], @runner.calls.last.first
  end

  test "a failed check keeps the backup ok and records its reason" do
    runner = FakeBackupRunner.new("check" => Outcome.new(exit_status: 1, stdout: "", stderr: "dial tcp: i/o timeout"))
    assert_equal 0, backup(runner: runner).call([ "run" ])
    assert_equal "ok", status.outcome
    assert_equal "failed", status.last_check_outcome
    assert_equal "destination_unreachable", status.check_error
    assert_equal NOW, status.last_check_at
    assert_includes @out.string, "[backup] check failed: destination_unreachable"
  end

  test "a failure at each step writes a failed status with its reason, and exits 1" do
    {
      "pg_dump" => [ "dump", Outcome.new(exit_status: 1, stdout: "", stderr: "could not connect to server"), "database_unreachable" ],
      "backup" => [ "backup", Outcome.new(exit_status: 12, stdout: "", stderr: "anything"), "wrong_password" ],
      "forget" => [ "forget", Outcome.new(exit_status: 1, stdout: "", stderr: "No space left on device"), "disk_full" ]
    }.each do |key, (step, outcome, reason)|
      previous_ok.write(Status.path(@root))
      @out = StringIO.new
      runner = FakeBackupRunner.new(key => outcome)

      assert_equal 1, backup(runner: runner).call([ "run" ]), step
      written = status
      assert_equal "failed", written.outcome, step
      assert_equal reason, written.error, step
      assert_equal NOW, written.finished_at, step
      assert_equal Time.utc(2026, 10, 1, 3), written.first_run_at, step
      assert_equal "ok", written.last_check_outcome, step
      assert_equal "[backup] failed at #{step}: #{reason}", @out.string.lines(chomp: true).last, step
      assert_equal key, runner.steps.last, "nothing runs after a failed #{step}"
      assert_empty Dir.children(@dump_dir), step
      if step == "forget"
        # The snapshot was taken and is good: it is the newest good backup.
        assert_equal [ "1a2b3c4d", 1_234, 100_000, NOW ],
          [ written.snapshot, written.database_bytes, written.files_bytes, written.last_ok_at ], step
      else
        assert_equal [ "99887766", 500, 7_000, Time.utc(2026, 11, 17, 3) ],
          [ written.snapshot, written.database_bytes, written.files_bytes, written.last_ok_at ], step
      end
    end
  end

  test "a tool that cannot be started is a failure, recorded as other" do
    runner = FakeBackupRunner.new("pg_dump" => ->(*) { raise Errno::ENOENT, "nice" })
    assert_equal 1, backup(runner: runner).call([ "run" ])
    assert_equal "other", status.error
    assert_equal "[backup] failed at dump: other", @out.string.lines(chomp: true).last
  end

  test "a backup with no summary from restic is a failure, recorded as other" do
    runner = FakeBackupRunner.new("backup" => Outcome.new(exit_status: 0, stdout: "not json\n", stderr: ""))
    assert_equal 1, backup(runner: runner).call([ "run" ])
    assert_equal "other", status.error
  end

  test "a missing secret is named, recorded as its reason, and no tool is started" do
    {
      "POSTGRES_PASSWORD" => "database_unreachable",
      "RESTIC_PASSWORD" => "wrong_password",
      "AWS_SECRET_ACCESS_KEY" => "destination_unreachable",
      "AWS_ACCESS_KEY_ID" => "destination_unreachable"
    }.each do |name, reason|
      @err = StringIO.new
      FileUtils.rm_f(Status.path(@root))
      assert_equal 1, backup(env: @env.merge(name => "")).call([ "run" ]), name
      assert_equal "Cannot run: #{name} is not set.\n", @err.string
      assert_equal "failed", status.outcome, name
      assert_equal reason, status.error, name
      assert_equal NOW, status.first_run_at, name
      assert_nil status.last_ok_at, name
    end
    assert_empty @runner.calls

    @err = StringIO.new
    backup(env: @env.except("POSTGRES_PASSWORD", "RESTIC_PASSWORD")).call([ "run" ])
    assert_equal "Cannot run: POSTGRES_PASSWORD and RESTIC_PASSWORD are not set.\n", @err.string
    assert_equal "database_unreachable", status.error
    HIDDEN.each { |value| refute_includes @err.string, value }
    assert_empty @runner.calls

    @err = StringIO.new
    assert_equal 1, backup(env: @env.except("RESTIC_PASSWORD")).call([ "list" ])
    assert_equal "Cannot list: RESTIC_PASSWORD is not set.\n", @err.string
    assert_empty @runner.calls

    local = @env.except("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY").merge("BACKUP_REPOSITORY" => "local:/repo")
    assert_equal 0, backup(env: local).call([ "run" ])
    assert_equal %w[pg_dump backup forget check], @runner.steps
  end

  test "a tool's message holding every secret reaches neither the output nor the status file" do
    leak = "#{HIDDEN.join(" ")} stderr-words"
    loud = Outcome.new(exit_status: 0, stdout: "#{HIDDEN.join(" ")} stdout-words\n", stderr: leak)
    script = {
      "pg_dump" => loud, "forget" => loud, "check" => loud,
      "backup" => Outcome.new(exit_status: 0, stdout: "#{HIDDEN.join(" ")}\n#{FakeBackupRunner.summary(9_999)}\n", stderr: leak),
      "snapshots" => loud, "init" => loud
    }
    assert_equal 0, backup(runner: FakeBackupRunner.new(script)).call([ "run" ])
    failing = FakeBackupRunner.new(script.merge("forget" => Outcome.new(exit_status: 1, stdout: leak, stderr: leak)))
    assert_equal 1, backup(runner: failing).call([ "run" ])
    texts = [ @out.string, @err.string, Status.path(@root).read ]
    HIDDEN.each { |value| texts.each { |text| refute_includes text, value } }
    texts.each { |text| refute_includes text, "stdout-words" }
    texts.each { |text| refute_includes text, "stderr-words" }

    %w[list init].each do |command|
      @out = StringIO.new
      @err = StringIO.new
      assert_equal 0, backup(runner: FakeBackupRunner.new(script)).call([ command ]), command
      assert_equal "#{([ "[hidden]" ] * HIDDEN.size).join(" ")} stdout-words\n", @out.string, command
      assert_empty @err.string, command
    end

    @err = StringIO.new
    failing = FakeBackupRunner.new("snapshots" => Outcome.new(exit_status: 12, stdout: "", stderr: leak))
    assert_equal 1, backup(runner: failing).call([ "list" ])
    assert_equal "[backup] list failed: wrong_password\n", @err.string
  end

  test "list and init run restic's own command" do
    backup.call([ "list" ])
    backup.call([ "init" ])
    assert_equal [ %w[restic snapshots], %w[restic init] ], @runner.calls.map(&:first)
  end

  test "children get only the variables they need" do
    backup(env: @env.except("PGUSER")).call([ "run" ])
    _, pg_env = @runner.call_for("pg_dump")
    assert_equal %w[PATH PGHOST PGPASSWORD PGUSER], pg_env.keys.sort
    assert_equal "postgres", pg_env["PGUSER"]
    assert_equal "pg-secret-4", pg_env["PGPASSWORD"]
    assert_equal "db", pg_env["PGHOST"]

    %w[backup forget check].each do |step|
      _, restic_env = @runner.call_for(step)
      assert_equal %w[AWS_ACCESS_KEY_ID AWS_DEFAULT_REGION AWS_SECRET_ACCESS_KEY HOME PATH RESTIC_PASSWORD RESTIC_REPOSITORY],
        restic_env.keys.sort, step
      assert_equal REPOSITORY, restic_env["RESTIC_REPOSITORY"]
      assert_equal "/home/backup", restic_env["HOME"]
    end

    runner = FakeBackupRunner.new
    backup(env: @env.merge("PGUSER" => "content_spiel").except("AWS_DEFAULT_REGION"), runner: runner).call([ "run" ])
    assert_equal "content_spiel", runner.call_for("pg_dump").last["PGUSER"]
    refute runner.call_for("backup").last.key?("AWS_DEFAULT_REGION")
  end

  test "run writes nothing in the files volume but its own folder" do
    before = tree(storage)
    backup.call([ "run" ])
    after = tree(storage)
    changed = (before.keys | after.keys).reject { |path| before[path] == after[path] }
    assert_not_empty changed
    assert changed.all? { |path| path == "backup" || path.start_with?("backup/") }, changed.inspect
  end

  test "restore refuses a target that is not empty, and lays out database.dump and files/" do
    target = Pathname(Dir.mktmpdir).join("restore")
    target.mkpath
    target.join("left").write("x")
    assert_equal 1, backup.call([ "restore", "latest", target.to_s ])
    assert_equal "#{target} is not empty: restore into an empty or new folder.\n", @err.string
    assert_empty @runner.calls
    target.join("left").delete

    runner = FakeBackupRunner.new("restore" => lambda do |argv, _env|
      into = argv[argv.index("--target") + 1]
      FileUtils.mkdir_p(File.join(into, @dump_dir.to_s))
      File.write(File.join(into, @dump_dir.to_s, "database.dump"), "dump")
      FileUtils.mkdir_p(File.join(into, storage, "ab"))
      File.write(File.join(into, storage, "ab", "image"), "image")
      Outcome.new(exit_status: 0, stdout: SECRETS.values.join, stderr: SECRETS.values.join)
    end)
    @out = StringIO.new
    assert_equal 0, backup(runner: runner).call([ "restore", "1a2b3c4d", target.to_s ])
    assert_equal %W[restic restore 1a2b3c4d --host #{SITE} --target #{target}/.restic], runner.calls.first.first
    assert_equal %w[database.dump files], Dir.children(target).sort
    assert_equal "dump", target.join("database.dump").read
    assert_equal "image", target.join("files", "ab", "image").read
    assert_equal "Restored snapshot 1a2b3c4d into #{target}: database.dump and files/. Nothing else was changed.\n",
      @out.string.lines.last
    HIDDEN.each { |value| refute_includes @out.string + @err.string, value }
  ensure
    FileUtils.remove_entry(target.dirname) if target
  end

  test "restore makes a target that does not exist, and a failed restore leaves nothing behind" do
    target = Pathname(Dir.mktmpdir).join("new", "restore")
    runner = FakeBackupRunner.new("restore" => Outcome.new(exit_status: 10, stdout: "", stderr: ""))
    assert_equal 1, backup(runner: runner).call([ "restore", "latest", target.to_s ])
    assert_equal "[backup] restore failed: destination_unreachable\n", @err.string
    assert_empty Dir.children(target)
  ensure
    FileUtils.remove_entry(target.dirname.dirname) if target
  end

  test "an unknown command, or none, prints the usage and exits 2" do
    [ [], [ "nope" ], [ "restore", "latest" ], [ "run", "extra" ] ].each do |argv|
      @err = StringIO.new
      assert_equal 2, backup.call(argv), argv.inspect
      listed = @err.string.lines.grep(/\A  \S/).map { |line| line.split.first }
      assert_equal Backup::COMMANDS, listed, argv.inspect
    end
    assert_empty @runner.calls
  end

  # macOS's CoreFoundation sets __CF_USER_TEXT_ENCODING inside every process.
  test "the runner hands the child only the given environment and a closed stdin, never through a shell" do
    script = "print ENV.keys.grep_v(/\\A__CF_/).sort.join(','), ' ', ARGV.inspect"
    outcome = Runner.new.call([ RbConfig.ruby, "-e", script, "$HOME; echo x" ], env: { "ONLY" => "1" })
    assert_equal 0, outcome.exit_status
    assert_equal "ONLY [\"$HOME; echo x\"]", outcome.stdout
    assert_empty outcome.stderr

    closed = Runner.new.call(%w[cat], env: { "PATH" => Backup::PATH })
    refute_equal 0, closed.exit_status
    assert_match(/Bad file descriptor/, closed.stderr)

    failed = Runner.new.call([ RbConfig.ruby, "-e", "$stderr.print 'no'; exit 3" ], env: {})
    assert_equal [ 3, "", "no" ], [ failed.exit_status, failed.stdout, failed.stderr ]
  end

  test "the runner's interrupt sends TERM to the running child, and is harmless with none" do
    runner = Runner.new
    runner.interrupt
    thread = Thread.new { runner.call([ RbConfig.ruby, "-e", "sleep 30" ], env: {}) }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    until runner.running?
      flunk "the child never started (thread alive: #{thread.alive?})" if !thread.alive? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
    runner.interrupt
    outcome = thread.value
    refute_equal 0, outcome.exit_status
  end

  test "list and init hide the repository with or without its trailing slash" do
    env = @env.merge("BACKUP_REPOSITORY" => "#{REPOSITORY}/")
    runner = FakeBackupRunner.new("snapshots" => Outcome.new(exit_status: 0, stdout: "at #{REPOSITORY}/ and #{REPOSITORY}\n", stderr: ""))
    assert_equal 0, backup(env: env, runner: runner).call([ "list" ])
    assert_equal "at [hidden] and [hidden]\n", @out.string
  end

  test "values that are not secret are read stripped, secrets as given" do
    env = @env.merge("BACKUP_REPOSITORY" => " #{REPOSITORY} ", "BACKUP_SITE" => " #{SITE}\n", "PGHOST" => " db ",
      "PGUSER" => " content_spiel ", "AWS_DEFAULT_REGION" => " auto ", "RESTIC_PASSWORD" => " spaced secret ")
    backup(env: env).call([ "run" ])
    pg_env = @runner.call_for("pg_dump").last
    assert_equal [ "db", "content_spiel" ], pg_env.values_at("PGHOST", "PGUSER")
    argv, restic_env = @runner.call_for("backup")
    assert_equal [ REPOSITORY, "auto", " spaced secret " ], restic_env.values_at("RESTIC_REPOSITORY", "AWS_DEFAULT_REGION", "RESTIC_PASSWORD")
    bare = FakeBackupRunner.bare(argv)
    assert_equal [ "--host", SITE ], bare[bare.index("--host"), 2]
  end

  test "next_run_at is the hour's next occurrence in UTC, strictly after now" do
    assert_equal Time.utc(2026, 11, 18, 3), Backup.next_run_at(Time.utc(2026, 11, 18, 2, 59), 3)
    assert_equal Time.utc(2026, 11, 19, 3), Backup.next_run_at(Time.utc(2026, 11, 18, 3, 0, 0), 3)
    assert_equal Time.utc(2026, 11, 19, 0), Backup.next_run_at(Time.utc(2026, 11, 18, 23, 30), 0)
    assert_equal Time.utc(2027, 1, 1, 0), Backup.next_run_at(Time.utc(2026, 12, 31, 23, 30), 0)
    assert_equal Time.utc(2026, 11, 18, 3), Backup.next_run_at(Time.new(2026, 11, 18, 3, 59, 0, "+02:00"), 3)
  end

  test "schedule sleeps until the hour, runs once a day, and does not retry a failure" do
    clock, sleeper, sleeps = fake_time(Time.utc(2026, 11, 18, 2, 59, 30))
    dumps = 0
    runner = FakeBackupRunner.new("pg_dump" => lambda do |argv, _env|
      dumps += 1
      next Outcome.new(exit_status: 1, stdout: "", stderr: "could not connect") if dumps == 1

      File.binwrite(argv[argv.index("--file") + 1], "x")
      Outcome.new(exit_status: 0, stdout: "", stderr: "")
    end)

    assert_equal 0, backup(clock: clock, sleeper: sleeper, runner: runner).schedule(runs: 2)
    assert_equal [ 30, 86_400 ], sleeps
    assert_equal 2, runner.steps.count("pg_dump")
    assert_equal "ok", status.outcome
    assert_equal Time.utc(2026, 11, 19, 3), status.finished_at
    assert_includes @out.string, "[backup] next run at 2026-11-18 03:00 UTC"
    assert_includes @out.string, "[backup] failed at dump: database_unreachable"

    clock, sleeper, sleeps = fake_time(Time.utc(2026, 11, 18, 2, 59, 30))
    backup(env: @env.merge("BACKUP_HOUR" => " 04 "), clock: clock, sleeper: sleeper, runner: FakeBackupRunner.new).schedule(runs: 1)
    assert_equal [ 3_630 ], sleeps
  end

  test "schedule refuses a BACKUP_HOUR that is not 0 to 23 and exits 1" do
    [ "24", "-1", "3am", "", " ", "3.0" ].each do |value|
      @err = StringIO.new
      assert_equal 1, backup(env: @env.merge("BACKUP_HOUR" => value)).call([ "schedule" ]), value.inspect
      assert_includes @err.string, "BACKUP_HOUR", value.inspect
      assert_includes @err.string, "0 to 23", value.inspect
    end
    assert_empty @runner.calls
  end

  test "unconfigured, schedule says so once a day and runs nothing" do
    clock, sleeper, sleeps = fake_time(NOW)
    assert_equal 0, backup(env: @env.except("BACKUP_REPOSITORY"), clock: clock, sleeper: sleeper).schedule(runs: 2)
    assert_equal [ Backup::NOT_CONFIGURED ] * 2, @out.string.lines(chomp: true)
    assert_equal [ 86_400 ], sleeps
    assert_empty @runner.calls
    assert_nil status
  end

  test "stop! while sleeping ends the schedule with 0; during a run it interrupts the tool and records the run as failed" do
    command = nil
    command = backup(sleeper: ->(_) { command.stop! })
    assert_equal 0, command.schedule
    assert_empty @runner.calls

    previous_ok.write(Status.path(@root))
    runner = FakeBackupRunner.new("backup" => lambda do |*|
      command.stop!
      Outcome.new(exit_status: 143, stdout: "", stderr: "")
    end)
    command = backup(runner: runner, sleeper: ->(_) { })
    assert_equal 143, command.schedule
    assert_equal 1, runner.interrupts
    assert_equal %w[pg_dump backup], runner.steps
    assert_equal [ "failed", "other", Time.utc(2026, 11, 17, 3) ], [ status.outcome, status.error, status.last_ok_at ]
    assert_empty Dir.children(@dump_dir)

    # A tool that finishes despite the stop still ends the run there.
    runner = FakeBackupRunner.new("forget" => lambda do |*|
      command.stop!
      Outcome.new(exit_status: 0, stdout: "", stderr: "")
    end)
    command = backup(runner: runner, sleeper: ->(_) { })
    assert_equal 143, command.schedule
    assert_equal %w[pg_dump backup forget], runner.steps
    assert_equal [ "failed", "other", "1a2b3c4d", NOW ], [ status.outcome, status.error, status.snapshot, status.last_ok_at ]

    # A check that the stop ended is no failed check: it stays due.
    previous_ok(last_check_at: Time.utc(2026, 10, 1, 3)).write(Status.path(@root))
    runner = FakeBackupRunner.new("check" => lambda do |*|
      command.stop!
      Outcome.new(exit_status: 143, stdout: "", stderr: "")
    end)
    command = backup(runner: runner, sleeper: ->(_) { })
    assert_equal 143, command.schedule
    assert_equal %w[pg_dump backup forget check], runner.steps
    assert_equal [ "failed", "other", "1a2b3c4d" ], [ status.outcome, status.error, status.snapshot ]
    assert_equal [ Time.utc(2026, 10, 1, 3), "ok" ], [ status.last_check_at, status.last_check_outcome ]
  end

  test "bin/backup ends its schedule at TERM or INT while it sleeps, with 0" do
    %w[TERM INT].each do |signal|
      IO.popen({ "BACKUP_REPOSITORY" => nil }, [ RbConfig.ruby, Rails.root.join("bin/backup").to_s, "schedule" ],
        err: File::NULL) do |io|
        assert_equal Backup::NOT_CONFIGURED, io.gets&.chomp, signal
        Process.kill(signal, io.pid)
        assert_nil io.gets, signal
      end
      assert_equal 0, $?.exitstatus, signal
    end
  end

  test "the command loads with plain Ruby, without Rails" do
    script = "require_relative #{Rails.root.join("lib/content_spiel/backup").to_s.inspect}; " \
      "print ContentSpiel::Backup::COMMANDS.join(','), ' ', defined?(Rails).inspect"
    output = IO.popen([ RbConfig.ruby, "--disable-gems", "-e", script ], &:read)
    assert_equal "run,schedule,list,restore,init nil", output
  end
end
