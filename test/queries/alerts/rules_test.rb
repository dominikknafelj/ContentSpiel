require "test_helper"

class Alerts::RulesTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 11, 16, 12, 7, 30)
  WINDOW_START = Time.utc(2026, 11, 16, 12, 0, 0)

  setup do
    Alerts::Alert.delete_all
    travel_to NOW
  end

  def event(action, at: NOW - 2.minutes, **attributes)
    Audit::Event.create!({ action:, channel: "web", occurred_at: at, last_occurred_at: at }.merge(attributes))
  end

  def apply(now: NOW) = Alerts::Rules.new(now:).apply

  def alert(kind) = Alerts::Alert.where(kind:).sole

  test "19 failed sign-ins in a window make no alert" do
    19.times { event("session.failed") }
    assert_equal 0, apply
    assert_equal 0, Alerts::Alert.count
  end

  test "exactly 20 mixed failures with one lock is one alert" do
    10.times { event("session.failed") }
    5.times { event("session.second_factor_failed") }
    5.times { event("session.confirmation_failed") }
    event("session.locked")
    assert_equal 1, apply
    found = alert("sign_in_failures")
    assert_equal 20, found.occurrences
    assert_equal({ "window_start" => WINDOW_START.iso8601, "failed" => 20, "locked" => 1 }, found.details)
    assert_equal "sign_in_failures|#{WINDOW_START.iso8601}", found.fingerprint
  end

  test "a second scan with more failures updates the same row and keeps its first seen and mailed times" do
    20.times { event("session.failed") }
    apply
    first = alert("sign_in_failures")
    first.update_columns(mailed_at: NOW)

    travel_to NOW + 1.minute
    3.times { event("session.failed", at: NOW + 30.seconds) }
    apply(now: NOW + 1.minute)

    assert_equal 1, Alerts::Alert.where(kind: "sign_in_failures").count
    again = alert("sign_in_failures")
    assert_equal 23, again.occurrences
    assert_equal 23, again.details["failed"]
    assert_equal first.first_seen_at, again.first_seen_at
    assert_equal NOW, again.mailed_at
    assert_operator again.last_seen_at, :>, first.last_seen_at
  end

  test "failures split across two windows make no alert" do
    10.times { event("session.failed", at: WINDOW_START - 2.minutes) }
    10.times { event("session.failed") }
    assert_equal 0, apply
  end

  test "access denied rows summing to 20 from two actors make one alert, and 19 none" do
    event("access.denied", occurrences: 12, user_id: users(:one).id)
    event("access.denied", occurrences: 7, user_id: users(:two).id)
    assert_equal 0, apply

    event("access.denied", occurrences: 1, user_id: users(:two).id)
    assert_equal 1, apply
    found = alert("access_denied_burst")
    assert_equal 20, found.occurrences
    assert_equal({ "window_start" => WINDOW_START.iso8601, "denied" => 20, "actors" => 2 }, found.details)
  end

  test "an access denied by nobody counts as one more actor" do
    event("access.denied", occurrences: 10, user_id: users(:one).id)
    event("access.denied", occurrences: 10)
    apply
    assert_equal 2, alert("access_denied_burst").details["actors"]
  end

  test "one request.limited makes one alert naming the sorted distinct limits" do
    event("request.limited", metadata: { "limit" => "default", "door" => "admin/passwords#create" })
    event("request.limited", metadata: { "limit" => "check", "door" => "admin/passwords#check" })
    event("request.limited", metadata: { "limit" => "check", "door" => "admin/passwords#check" })
    assert_equal 1, apply
    assert_equal({ "window_start" => WINDOW_START.iso8601, "limited" => 3, "limits" => %w[check default] }, alert("request_limited").details)
  end

  test "an owner change is one alert, once however often the scan runs" do
    named = users(:two)
    named.update_columns(name: "Dana Doe")
    owner_event = event("user.owner_changed", user_id: named.id, subject_label: "Pat", field_changes: { "owner" => [ false, true ] })
    apply
    apply
    found = alert("owner_changed")
    assert_equal({ "audit_event_id" => owner_event.id, "subject_label" => "Pat", "actor_name" => "Dana Doe", "now_owner" => true }, found.details)
    assert_equal "audit|#{owner_event.id}", found.fingerprint
    assert_equal 1, Alerts::Alert.count
  end

  test "an owner change by the system has no actor name, and a removal is not now_owner" do
    event("user.owner_changed", subject_label: "Pat", field_changes: { "owner" => [ true, false ] })
    apply
    assert_nil alert("owner_changed").details["actor_name"]
    assert_equal false, alert("owner_changed").details["now_owner"]
  end

  test "a token issued is one alert with its name, group and actor" do
    issued = event("token.issued", user_id: users(:one).id, metadata: { "group" => "Admin", "name" => "CI" })
    apply
    assert_equal({ "audit_event_id" => issued.id, "token_name" => "CI", "group_name" => "Admin", "actor_name" => PersonName.of(users(:one)) }, alert("token_issued").details)
  end

  test "an owner change 40 minutes old makes no alert" do
    event("user.owner_changed", at: NOW - 40.minutes, field_changes: { "owner" => [ false, true ] })
    assert_equal 0, apply
  end

  test "no alert holds an address or a typed email" do
    20.times { event("session.failed", ip: "203.0.113.9", metadata: { "email" => "typed@victim.example" }) }
    event("request.limited", ip: "203.0.113.9", metadata: { "limit" => "default", "door" => "x#y" })
    event("user.owner_changed", ip: "203.0.113.9", subject_label: "Pat", field_changes: { "owner" => [ false, true ] })
    event("token.issued", ip: "203.0.113.9", metadata: { "group" => "Admin", "name" => "CI" })
    apply
    json = Alerts::Alert.all.map { |alert| alert.details.to_json }.join
    assert_no_match(/203\.0\.113\.9|typed@victim/, json)
    assert_equal 4, Alerts::Alert.count
  end

  test "a nameless subject user's address never reaches an alert" do
    nameless = users(:two)
    event("user.owner_changed", subject_type: "User", subject_id: nameless.id, subject_label: nameless.email_address, field_changes: { "owner" => [ false, true ] })
    event("user.owner_changed", subject_label: "gone@example.com", field_changes: { "owner" => [ false, true ] })
    apply
    json = Alerts::Alert.all.map { |alert| alert.details.to_json }.join
    assert_no_match(/example\.com/, json)
    assert_equal %w[gone two], Alerts::Alert.all.map { |alert| alert.details["subject_label"] }.sort
  end

  test "a late scan in the next window still alerts on the previous window's failures" do
    20.times { event("session.failed") }
    late = WINDOW_START + 20.minutes
    assert_equal 1, apply(now: late)
    assert_equal WINDOW_START.iso8601, alert("sign_in_failures").details["window_start"]
  end

  test "a per-event alert at the two-window boundary is made, one just before it is not" do
    inside = event("user.owner_changed", at: WINDOW_START - 15.minutes, field_changes: { "owner" => [ false, true ] })
    event("user.owner_changed", at: WINDOW_START - 15.minutes - 1.second, field_changes: { "owner" => [ false, true ] })
    apply
    assert_equal [ "audit|#{inside.id}" ], Alerts::Alert.pluck(:fingerprint)
  end
end
