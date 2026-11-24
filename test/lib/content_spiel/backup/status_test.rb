require "test_helper"
require "tmpdir"

class ContentSpiel::Backup::StatusTest < ActiveSupport::TestCase
  Status = ContentSpiel::Backup::Status

  setup { @root = Pathname(Dir.mktmpdir) }
  teardown { FileUtils.remove_entry(@root) }

  def full(**over)
    Status.new(finished_at: Time.utc(2026, 11, 17, 3, 0, 5), outcome: "ok", snapshot: "abc123",
      database_bytes: 1000, files_bytes: 2000, duration_seconds: 12.5,
      first_run_at: Time.utc(2026, 11, 1, 3), last_ok_at: Time.utc(2026, 11, 17, 3, 0, 5),
      last_check_at: Time.utc(2026, 11, 10, 4), last_check_outcome: "ok", check_error: nil,
      error: nil, cms_version: "0.10.0", **over)
  end

  test "a status written is read back whole, times in UTC" do
    path = Status.path(@root)
    assert_equal @root.join("storage", "backup", "status.json"), path
    full.write(path)
    assert_equal full, Status.read(path)
    assert_match(/"finished_at": ?"2026-11-17T03:00:05Z"/, path.read)
    assert_predicate Status.read(path).finished_at, :utc?
    assert_equal 0o644, path.stat.mode & 0o777
  end

  test "a write is whole or absent: a temp file and a rename" do
    path = Status.path(@root)
    full.write(path)
    before = path.read
    with_singleton_override(File, :rename, ->(*) { raise Errno::EIO }) do
      assert_raises(Errno::EIO) { full(snapshot: "other").write(path) }
    end
    assert_equal before, path.read
    assert_empty Dir.glob("#{path}.tmp*")
  end

  test "no file reads as nil, and a file that is not the status reads as unreadable" do
    path = Status.path(@root)
    assert_nil Status.read(path)
    FileUtils.mkdir_p(path.dirname)
    [ "{", "[]", '{"outcome":"ok","database_bytes":[1]}', '{"outcome":"ok","snapshot":5}', '{"outcome":"ok","duration_seconds":"x"}', '{"outcome":"maybe"}', '{"outcome":"failed","error":"boom"}' ].each do |text|
      path.write(text)
      status = Status.read(path)
      assert_predicate status, :unreadable?, text
      assert_equal "unreadable", status.outcome
      assert_nil status.snapshot
    end
  end

  test "the age of the good backup is never negative" do
    now = Time.utc(2026, 11, 17, 12)
    assert_equal 0.0, full(last_ok_at: now + 60).good_backup_age(now)
    assert_equal 3600.0, full(last_ok_at: now - 3600).good_backup_age(now)
    assert_nil full(last_ok_at: nil).good_backup_age(now)
    assert_equal 0.0, full(first_run_at: now + 5).since_first_run(now)
  end

  test "the predicates and the total" do
    assert_predicate full, :ok?
    assert_equal 3000, full.total_bytes
    assert_equal 0, Status.unreadable.total_bytes
    assert_predicate full(last_check_outcome: "failed"), :check_failed?
    refute_predicate full, :check_failed?
  end

  test "the status file names no secret field" do
    Status.members.each { |m| assert_no_match(/password|key|repository/, m.to_s) }
  end
end
