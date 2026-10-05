require "test_helper"

# `Audit::Filter`: the audit log's filters (design pass round 3, Task 15).
class Audit::FilterTest < ActiveSupport::TestCase
  def filter(params = nil, today: Date.new(2026, 10, 4), **keywords) = Audit::Filter.new(ActiveSupport::HashWithIndifferentAccess.new(params || keywords), today:)

  def event(at, **attributes)
    Audit::Event.create!({ action: "test.filter", channel: "admin", occurred_at: at, last_occurred_at: at }.merge(attributes))
  end

  test "junk values fall back to all, never an error" do
    f = filter(user_id: "1; DROP TABLE", event_action: "", subject_type: "Nope", subject_id: "5", channel: "fax", range: "yesterday", from: "x", to: "9999-99-99")

    assert_empty f.to_params
    assert_not f.active?
    assert_nothing_raised { f.scope.to_a }
  end

  test "a subject id needs a valid subject type" do
    assert_nil filter(subject_id: "5").subject_id
    assert_equal({ "subject_type" => "Post", "subject_id" => "5" }, filter(subject_type: "Post", subject_id: "5").to_params)
  end

  test "date presets are the site's days, computed from today" do
    Time.use_zone("Pacific/Auckland") do
      early = event(Time.zone.local(2026, 10, 4, 0, 30)) # just after midnight in Auckland (still 3 Oct in UTC)
      late = event(Time.zone.local(2026, 10, 3, 23, 30))
      week_ago = event(Time.zone.local(2026, 9, 28, 12))
      long_ago = event(Time.zone.local(2026, 9, 27, 12))

      assert_equal [ early.id ], filter({ range: "today" }).scope.where(action: "test.filter").ids
      assert_equal [ early.id, late.id, week_ago.id ].sort, filter({ range: "7" }).scope.where(action: "test.filter").ids.sort # 28 Sep .. 4 Oct
      assert_not_includes filter({ range: "7" }).scope.ids, long_ago.id
      assert_includes filter({ range: "30" }).scope.ids, long_ago.id
    end
  end

  test "a custom range is inclusive of both days, in the site zone, and a reversed one is swapped" do
    Time.use_zone("Europe/Berlin") do
      inside = event(Time.zone.local(2026, 6, 30, 23, 59))
      before = event(Time.zone.local(2026, 5, 31, 23, 59))
      after = event(Time.zone.local(2026, 7, 1, 0, 1))

      ids = filter({ range: "custom", from: "2026-06-01", to: "2026-06-30" }).scope.ids
      assert_includes ids, inside.id
      assert_not_includes ids, before.id
      assert_not_includes ids, after.id
      assert_equal ids.sort, filter({ range: "custom", from: "2026-06-30", to: "2026-06-01" }).scope.ids.sort
      assert_equal({ "range" => "custom", "from" => "2026-06-01", "to" => "2026-06-30" }, filter({ range: "custom", from: "2026-06-30", to: "2026-06-01" }).to_params)
    end
  end

  test "from and to alone are a custom range (the old links)" do
    f = filter(from: "2026-06-01")
    assert f.custom?
    assert_equal Date.new(2026, 6, 1), f.from
  end

  test "from and to mean nothing for a preset" do
    f = filter(range: "7", from: "2020-01-01", to: "2020-01-02")
    assert_nil f.from
    assert_equal({ "range" => "7" }, f.to_params)
  end

  test "the channel filter: admin, mcp, and other (anything else, nil included)" do
    admin = event(Time.current, channel: "admin")
    mcp = event(Time.current, channel: "mcp")
    system = event(Time.current, channel: "system")
    none = event(Time.current, channel: nil)

    assert_equal [ admin.id ], filter(channel: "admin").scope.where(id: [ admin, mcp, system, none ]).ids
    assert_equal [ mcp.id ], filter(channel: "mcp").scope.where(id: [ admin, mcp, system, none ]).ids
    assert_equal [ system.id, none.id ].sort, filter(channel: "other").scope.where(id: [ admin, mcp, system, none ]).ids.sort
  end

  test "the legacy MediaAsset type is part of Media asset" do
    legacy = event(Time.current, subject_type: "MediaAsset", subject_id: 7)
    current = event(Time.current, subject_type: "Media::Asset", subject_id: 7)

    assert_equal [ legacy.id, current.id ].sort, filter(subject_type: "Media::Asset", subject_id: "7").scope.ids.sort
  end
end
