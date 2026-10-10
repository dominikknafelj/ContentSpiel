require "test_helper"

# The row of one person's tab on one record (presence spec §5.2): each
# method is one statement and none writes anything but its own row.
class Presence::MarkTest < ActiveSupport::TestCase
  setup do
    @page = create_page(title: "Pricing")
    @user = users(:two)
    @tab = "tab-aaaaaaaa"
  end

  def arrive(tab: @tab, user: @user, record: @page, **options) = Presence::Mark.arrive(user:, record:, tab:, **options)

  def report(state, tab: @tab) = Presence::Mark.report(user: @user, record: @page, tab:, state:)

  test "arriving writes a here row for the polymorphic type, the tab and now, and answers the token" do
    token = nil
    freeze_time do
      token = arrive
      mark = Presence::Mark.sole
      assert_equal [ @user.id, "Page", @page.id, @tab, "here", token ], mark.values_at(:user_id, :record_type, :record_id, :tab, :state, :token)
      assert_match(/\A\h{16}\z/, token)
      assert_equal [ Time.current ] * 3, mark.values_at(:seen_at, :arrived_at, :state_at)
    end
    arrive(record: create_media_asset)
    assert_equal "Media::Asset", Presence::Mark.order(:id).last.record_type
  end

  test "arriving can carry the state and the token of a subscription that is being healed" do
    arrive(token: "0123456789abcdef", state: "away")
    mark = Presence::Mark.sole
    assert_equal [ "away", "0123456789abcdef" ], mark.values_at(:state, :token)
  end

  test "arriving twice from one tab is one row: the newer token wins and the first arrival is kept" do
    first = second = nil
    travel_to Time.zone.local(2026, 10, 10, 12, 0, 0) do
      first = arrive
      report("away")
    end
    travel_to Time.zone.local(2026, 10, 10, 12, 0, 20) do
      second = arrive
    end
    mark = Presence::Mark.sole
    assert_not_equal first, second
    assert_equal second, mark.token
    assert_equal Time.zone.local(2026, 10, 10, 12, 0, 0), mark.arrived_at
    assert_equal Time.zone.local(2026, 10, 10, 12, 0, 20), mark.seen_at
    assert_equal "here", mark.state
  end

  test "a second tab, a second person and a second record are rows of their own" do
    arrive
    arrive(tab: "tab-bbbbbbbb")
    arrive(user: users(:one))
    arrive(record: create_page(title: "Other"))
    assert_equal 4, Presence::Mark.count
  end

  test "each method is one statement" do
    token = nil
    assert_equal 1, capture_sql { token = arrive }.size
    assert_equal 1, capture_sql { report("away") }.size
    assert_equal 1, capture_sql { Presence::Mark.beat(user: @user, record: @page, tab: @tab) }.size
    assert_equal 1, capture_sql { Presence::Mark.leave(user: @user, record: @page, tab: @tab, token:) }.size
  end

  test "report says whether the row is there, always moves seen_at and moves state_at only with a change" do
    travel_to(Time.zone.local(2026, 10, 10, 12, 0, 0)) { arrive }
    travel_to(Time.zone.local(2026, 10, 10, 12, 5, 0)) { assert report("away") }
    mark = Presence::Mark.sole
    assert_equal [ "away", Time.zone.local(2026, 10, 10, 12, 5, 0), Time.zone.local(2026, 10, 10, 12, 5, 0) ], mark.values_at(:state, :seen_at, :state_at)

    travel_to(Time.zone.local(2026, 10, 10, 12, 9, 0)) { assert report("away") }
    mark = Presence::Mark.sole
    assert_equal Time.zone.local(2026, 10, 10, 12, 9, 0), mark.seen_at
    assert_equal Time.zone.local(2026, 10, 10, 12, 5, 0), mark.state_at

    travel_to(Time.zone.local(2026, 10, 10, 12, 10, 0)) { assert report("here") }
    assert_equal Time.zone.local(2026, 10, 10, 12, 10, 0), Presence::Mark.sole.state_at

    assert_not report("away", tab: "tab-cccccccc")
  end

  test "report ignores a state that is not known" do
    arrive
    [ "gone", "", nil, "HERE", :away, 3 ].each { |state| assert_not report(state), state.inspect }
    assert_equal "here", Presence::Mark.sole.state
  end

  test "beat moves seen_at and nothing else, and answers false for a row that is not there" do
    travel_to(Time.zone.local(2026, 10, 10, 12, 0, 0)) { arrive }
    travel_to(Time.zone.local(2026, 10, 10, 12, 0, 30)) { assert Presence::Mark.beat(user: @user, record: @page, tab: @tab) }
    mark = Presence::Mark.sole
    assert_equal Time.zone.local(2026, 10, 10, 12, 0, 30), mark.seen_at
    assert_equal Time.zone.local(2026, 10, 10, 12, 0, 0), mark.state_at
    assert_not Presence::Mark.beat(user: @user, record: @page, tab: "tab-cccccccc")
    assert_not Presence::Mark.beat(user: users(:one), record: @page, tab: @tab)
  end

  test "leave deletes the row of that token only: a late leave of an older subscription deletes nothing" do
    old = arrive
    new = arrive
    arrive(tab: "tab-bbbbbbbb")
    assert_not Presence::Mark.leave(user: @user, record: @page, tab: @tab, token: old)
    assert_equal 2, Presence::Mark.count
    assert Presence::Mark.leave(user: @user, record: @page, tab: @tab, token: new)
    assert_equal [ "tab-bbbbbbbb" ], Presence::Mark.pluck(:tab)
  end

  test "fresh is the last STALE_AFTER" do
    assert_equal 150.seconds, Presence::STALE_AFTER
    arrive
    Presence::Mark.update_all(seen_at: 151.seconds.ago) # version: none (a test of presence)
    assert_empty Presence::Mark.fresh
    Presence::Mark.update_all(seen_at: 149.seconds.ago) # version: none (a test of presence)
    assert_equal 1, Presence::Mark.fresh.count
  end

  test "the database refuses a state it does not know" do
    arrive
    assert_raises(ActiveRecord::StatementInvalid) { Presence::Mark.update_all(state: "gone") } # version: none (a test of presence)
  end

  test "a row goes with its user" do
    arrive
    assert Users::Destroy.call(@user, actor: nil).ok?
    assert_equal 0, Presence::Mark.count
  end

  test "presence writes nothing but its own row: not the record, not the content version, not the audit log" do
    updated_at = @page.reload.updated_at
    version = PublicSite::Version.current
    events = Audit::Event.count
    token = arrive
    report("away")
    Presence::Mark.beat(user: @user, record: @page, tab: @tab)
    Presence::Mark.leave(user: @user, record: @page, tab: @tab, token:)
    assert_equal updated_at, @page.reload.updated_at
    assert_equal version, PublicSite::Version.current
    assert_equal events, Audit::Event.count
  end
end
