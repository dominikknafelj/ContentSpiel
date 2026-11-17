require "test_helper"

class Alerts::AlertTest < ActiveSupport::TestCase
  setup { Alerts::Alert.delete_all }

  def make(kind: "error", seen: Time.current, mailed: nil, **details)
    Alerts::Alert.create!(kind: kind, fingerprint: SecureRandom.hex(8), details: details,
                          first_seen_at: seen, last_seen_at: seen, mailed_at: mailed)
  end

  test "the kind must be one of the kinds" do
    assert_not Alerts::Alert.new(kind: "nope", fingerprint: "a", first_seen_at: Time.current, last_seen_at: Time.current).valid?
    Alerts::Alert::KINDS.each { |kind| assert make(kind: kind).persisted? }
  end

  test "security kinds are all but error" do
    assert_equal Alerts::Alert::KINDS - %w[error], Alerts::Alert::SECURITY_KINDS
    assert_not make(kind: "error").security?
    assert make(kind: "owner_changed").security?
  end

  test "a fingerprint is unique in the database" do
    make.update_columns(fingerprint: "same")
    assert_raises(ActiveRecord::RecordNotUnique) do
      Alerts::Alert.insert!({ kind: "error", fingerprint: "same", first_seen_at: Time.current, last_seen_at: Time.current })
    end
  end

  test "details default to an empty hash and occurrences to one" do
    alert = Alerts::Alert.create!(kind: "error", fingerprint: "d", first_seen_at: Time.current, last_seen_at: Time.current)
    assert_equal({}, alert.reload.details)
    assert_equal 1, alert.occurrences
  end

  test "recent is the newest ten of the last seven days" do
    now = Time.current
    12.times { |i| make(seen: now - i.hours) }
    old = make(seen: now - 8.days)

    recent = Alerts::Alert.recent(now).to_a
    assert_equal 10, recent.size
    assert_equal recent.sort_by(&:last_seen_at).reverse, recent
    assert_not_includes recent, old
    assert_equal [ old ], Alerts::Alert.where(last_seen_at: ...(now - 7.days)).to_a
  end

  test "expired is only what was last seen over thirty days ago" do
    now = Time.current
    old = make(seen: now - 31.days)
    make(seen: now - 29.days)

    assert_equal [ old ], Alerts::Alert.expired(now).to_a
  end

  test "due covers never mailed, quiet since, seen since mailed recently, and seen since mailed long ago" do
    now = Time.current
    never = make(seen: now - 5.minutes)
    quiet = make(seen: now - 3.hours, mailed: now - 2.hours)
    recently = make(seen: now - 1.minute, mailed: now - 59.minutes)
    long_ago = make(seen: now - 1.minute, mailed: now - 61.minutes)

    due = Alerts::Alert.due(now).to_a
    assert_includes due, never
    assert_not_includes due, quiet
    assert_not_includes due, recently
    assert_includes due, long_ago
  end

  test "last_mailed_at is the newest mail" do
    assert_nil Alerts::Alert.last_mailed_at
    now = Time.current.change(usec: 0)
    make(mailed: now - 2.hours)
    make(mailed: now)
    assert_equal now, Alerts::Alert.last_mailed_at
  end

  test "a sentence is its wording's key and its values, and nothing else from details" do
    extra = { secret: "x", handled: false, source: "s" }
    cases = {
      "error" => [ { error_class: "RuntimeError", place: "app/a.rb:1" }, "error", { error_class: "RuntimeError", place: "app/a.rb:1" } ],
      "sign_in_failures" => [ { failed: 21, locked: 2 }, "sign_in_failures", { failed: 21, locked: 2, minutes: 15 } ],
      "owner_changed" => [ { subject_label: "Ana", actor_name: "Ben", now_owner: true }, "owner_made_by", { subject_label: "Ana", actor_name: "Ben", now_owner: true } ],
      "token_issued" => [ { token_name: "T", group_name: "G", actor_name: "Ben" }, "token_issued_by", { token_name: "T", group_name: "G", actor_name: "Ben" } ],
      "access_denied_burst" => [ { denied: 20, actors: 3 }, "access_denied_burst", { denied: 20, actors: 3, minutes: 15, count: 3 } ],
      "request_limited" => [ { limited: 4, limits: %w[forms search] }, "request_limited", { limited: 4, limits: "forms, search", minutes: 15, count: 4 } ]
    }
    cases.each do |kind, (details, key, values)|
      sentence = make(kind: kind, **details, **extra).sentence
      assert_equal key, sentence.key, kind
      assert_equal values, sentence.values, kind
    end
  end

  test "a sentence's key is the variant its values ask for" do
    {
      [ "error", { error_class: "RuntimeError", place: nil } ] => "error_nowhere",
      [ "owner_changed", { subject_label: "Ana", actor_name: nil, now_owner: true } ] => "owner_made",
      [ "owner_changed", { subject_label: "Ana", actor_name: "Ben", now_owner: false } ] => "owner_removed_by",
      [ "owner_changed", { subject_label: "Ana", actor_name: nil, now_owner: false } ] => "owner_removed",
      [ "token_issued", { token_name: "T", group_name: "G", actor_name: nil } ] => "token_issued"
    }.each do |(kind, details), key|
      assert_equal key, make(kind: kind, **details).sentence.key, details.inspect
    end
  end

  test "the audit log's filter: an event alert's one event, a window alert's actions in its span, nothing for an error" do
    assert_equal({ event_id: 812 }, make(kind: "owner_changed", audit_event_id: 812, subject_label: "Ana").audit_filter)
    assert_equal({ event_id: 9 }, make(kind: "token_issued", audit_event_id: 9, token_name: "deploy").audit_filter)
    assert_equal({ actions: %w[session.failed session.second_factor_failed session.confirmation_failed],
                   after: "2026-11-16T12:00:00Z", before: "2026-11-16T12:15:00Z" },
      make(kind: "sign_in_failures", window_start: "2026-11-16T12:00:00Z", failed: 22).audit_filter)
    assert_equal %w[access.denied], make(kind: "access_denied_burst", window_start: "2026-11-16T12:00:00Z").audit_filter[:actions]
    assert_equal %w[request.limited], make(kind: "request_limited", window_start: "2026-11-16T12:00:00Z").audit_filter[:actions]

    assert_nil make(kind: "error", error_class: "RuntimeError").audit_filter
    assert_nil make(kind: "sign_in_failures", failed: 22).audit_filter, "no window, no link: never the whole log"
    assert_nil make(kind: "sign_in_failures", window_start: "soon").audit_filter
  end
end
