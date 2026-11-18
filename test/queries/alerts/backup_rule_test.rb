require "test_helper"

# The backup alert: one row per UTC day while the newest good backup is two
# days old, none ever succeeded two days after the first run, or the monthly
# check failed.
class Alerts::BackupRuleTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  NOW = Time.utc(2026, 11, 20, 12, 0)

  setup { Alerts::Alert.delete_all }

  def status(**fields)
    ContentSpiel::Backup::Status.new(**ContentSpiel::Backup::Status.members.to_h { |m| [ m, nil ] }, outcome: "ok", **fields)
  end

  def apply(status, now: NOW, running_version: :none, off: false)
    Alerts::BackupRule.new(now: now, status: status, running_version: running_version, off: off).apply
  end

  def every(hours) = ContentSpiel::Backup::RunningVersion.new(cms_version: ContentSpiel::VERSION, started_at: NOW - 3.days, every_hours: hours)

  test "no status file, or an unreadable one, raises nothing" do
    Dir.mktmpdir do |root|
      with_singleton_override(Rails, :root, -> { Pathname(root) }) do
        assert_equal 0, Alerts::BackupRule.new(now: NOW, off: false).apply
        ContentSpiel::Backup::Status.path(root).tap { |path| path.dirname.mkpath }.write("not json")
        assert_equal 0, Alerts::BackupRule.new(now: NOW, off: false).apply
      end
    end
    assert_equal 0, apply(ContentSpiel::Backup::Status.unreadable)
    assert_equal 0, apply(nil)
    assert_equal 0, Alerts::Alert.count
  end

  test "47 hours is no alert, 48 is one with its hours" do
    assert_equal 0, apply(status(last_ok_at: NOW - 47.hours, first_run_at: NOW - 30.days))
    assert_equal 1, apply(status(last_ok_at: NOW - 48.hours, first_run_at: NOW - 30.days))

    alert = Alerts::Alert.sole
    assert_equal "backup_stale", alert.kind
    assert_equal "backup_stale|2026-11-20", alert.fingerprint
    assert_equal({ "reason" => "stale", "hours" => 48 }, alert.details)
    assert_equal "backup_stale", alert.sentence.key
    assert_equal 48, alert.sentence.values[:hours]
  end

  test "BACKUPS=off inserts nothing, whatever the status says" do
    assert_equal 0, apply(status(last_ok_at: NOW - 30.days, first_run_at: NOW - 60.days), off: true)
    assert_equal 0, apply(status(outcome: "failed", error: "other", first_run_at: NOW - 60.days), off: true)
    assert_equal 0, apply(status(last_ok_at: NOW - 1.hour, first_run_at: NOW - 30.days,
      last_check_at: NOW - 1.hour, last_check_outcome: "failed", check_error: "other"), off: true)
    assert_equal 0, Alerts::Alert.count
  end

  test "the alert follows the accessory's cadence: two intervals, 12 hours at 6 and still 48 at a day" do
    assert_equal 0, apply(status(last_ok_at: NOW - 11.hours - 59.minutes, first_run_at: NOW - 30.days), running_version: every(6))
    assert_equal 1, apply(status(last_ok_at: NOW - 12.hours, first_run_at: NOW - 30.days), running_version: every(6))
    assert_equal({ "reason" => "stale", "hours" => 12 }, Alerts::Alert.sole.details)
    Alerts::Alert.delete_all

    assert_equal 0, apply(status(outcome: "failed", error: "other", first_run_at: NOW - 11.hours), running_version: every(6))
    assert_equal 1, apply(status(outcome: "failed", error: "other", first_run_at: NOW - 12.hours), running_version: every(6))
    Alerts::Alert.delete_all

    [ every(24), :none ].each do |running|
      assert_equal 0, apply(status(last_ok_at: NOW - 47.hours, first_run_at: NOW - 30.days), running_version: running)
      assert_equal 1, apply(status(last_ok_at: NOW - 48.hours, first_run_at: NOW - 30.days), running_version: running)
      Alerts::Alert.delete_all
    end
  end

  test "a failed run alone alerts nothing" do
    assert_equal 0, apply(status(outcome: "failed", error: "other", finished_at: NOW - 1.hour,
      last_ok_at: NOW - 1.hour, first_run_at: NOW - 30.days))
  end

  test "never succeeded: an alert 48 hours after the first run" do
    assert_equal 0, apply(status(outcome: "failed", error: "other", first_run_at: NOW - 47.hours))
    assert_equal 1, apply(status(outcome: "failed", error: "other", first_run_at: NOW - 50.hours))

    alert = Alerts::Alert.sole
    assert_equal({ "reason" => "never", "hours" => 50 }, alert.details)
    assert_equal "backup_never", alert.sentence.key
  end

  test "a failed check alerts even when backups are fresh" do
    assert_equal 1, apply(status(last_ok_at: NOW - 1.hour, first_run_at: NOW - 30.days,
      last_check_at: NOW - 1.hour, last_check_outcome: "failed", check_error: "other"))

    alert = Alerts::Alert.sole
    assert_equal({ "reason" => "check_failed", "hours" => nil }, alert.details)
    assert_equal "backup_check_failed", alert.sentence.key
  end

  test "a stale backup seen every minute of a day is one row, mailed once" do
    day = Time.utc(2026, 11, 20)
    stale = status(last_ok_at: day - 5.days, first_run_at: day - 30.days)
    inserted = 0

    with_mail_state(:working) do
      with_site_address("https://docs.example.org") do
        assert_emails(User.owners.count) do
          1440.times do |minute|
            now = day + minute.minutes
            inserted += apply(stale, now: now)
            Alerts::Mailing.new(now: now).deliver
          end
        end
      end
    end

    assert_equal 1, inserted
    alert = Alerts::Alert.sole
    assert_not_nil alert.mailed_at
    assert_empty Alerts::Alert.due(alert.mailed_at + 2.hours)
    assert_empty Alerts::Alert.due(day + 24.hours)
  end

  test "the next day is a new alert" do
    stale = status(last_ok_at: NOW - 5.days, first_run_at: NOW - 30.days)
    apply(stale)
    apply(stale, now: NOW + 1.day)

    assert_equal %w[backup_stale|2026-11-20 backup_stale|2026-11-21], Alerts::Alert.order(:fingerprint).pluck(:fingerprint)
  end
end
