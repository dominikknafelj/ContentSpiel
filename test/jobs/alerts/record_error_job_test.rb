require "test_helper"

class Alerts::RecordErrorJobTest < ActiveJob::TestCase
  setup { Alerts::Alert.delete_all }

  def record(at:, place: "app/models/page.rb:120", error_class: "RuntimeError")
    Alerts::RecordErrorJob.perform_now(error_class: error_class, place: place, source: "application.action_dispatch", handled: false, at: at)
  end

  test "the first report makes a row with the four details and nothing else" do
    at = Time.zone.parse("2026-11-16 10:00:00")
    record(at: at)

    alert = Alerts::Alert.sole
    assert_equal "error", alert.kind
    assert_equal 1, alert.occurrences
    assert_equal Alerts::Alert.fingerprint_for_error("RuntimeError", "app/models/page.rb:120"), alert.fingerprint
    assert_equal({ "error_class" => "RuntimeError", "place" => "app/models/page.rb:120", "source" => "application.action_dispatch", "handled" => false }, alert.details)
    assert_equal at, alert.first_seen_at
    assert_equal at, alert.last_seen_at
    assert_nil alert.mailed_at
  end

  test "the same class at the same place counts on the same row" do
    first = Time.zone.parse("2026-11-16 10:00:00")
    record(at: first)
    record(at: first + 5.minutes)

    alert = Alerts::Alert.sole
    assert_equal 2, alert.occurrences
    assert_equal first, alert.first_seen_at
    assert_equal first + 5.minutes, alert.last_seen_at
  end

  test "a report that arrives late counts and does not move last_seen_at back" do
    first = Time.zone.parse("2026-11-16 10:00:00")
    record(at: first + 5.minutes)
    record(at: first)

    alert = Alerts::Alert.sole
    assert_equal 2, alert.occurrences
    assert_equal first + 5.minutes, alert.last_seen_at
  end

  test "another place, or another class, is another row" do
    at = Time.current
    record(at: at)
    record(at: at, place: "app/models/post.rb:3")
    record(at: at, error_class: "KeyError")
    record(at: at, place: nil)

    assert_equal 4, Alerts::Alert.count
    assert_equal [ 1 ], Alerts::Alert.distinct.pluck(:occurrences)
  end

  test "the fingerprint is the SHA256 of the kind, the class and the place" do
    fingerprint = Alerts::Alert.fingerprint_for_error("RuntimeError", "app/models/page.rb:120")

    assert_equal Digest::SHA256.hexdigest("error|RuntimeError|app/models/page.rb:120"), fingerprint
    assert_equal 64, fingerprint.length
    assert_equal Digest::SHA256.hexdigest("error|RuntimeError|"), Alerts::Alert.fingerprint_for_error("RuntimeError", nil)
  end

  test "is on the default queue" do
    assert_equal "default", Alerts::RecordErrorJob.new.queue_name
  end
end
