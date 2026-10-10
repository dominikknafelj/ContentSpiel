require "test_helper"

# The row of one person's tab on one record (presence spec §5.2): each
# method is one statement and none writes anything but its own row.
class Presence::MarkTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @page = create_page(title: "Pricing")
    @user = users(:two)
    @tab = "tab-aaaaaaaa"
  end

  def arrive(tab: @tab, user: @user, record: @page) = Presence::Mark.arrive(user:, record:, tab:)

  test "arriving writes a here row for the polymorphic type, the tab and now" do
    freeze_time do
      arrive
      mark = Presence::Mark.sole
      assert_equal [ @user.id, "Page", @page.id, @tab, "here" ], mark.values_at(:user_id, :record_type, :record_id, :tab, :state)
      assert_equal Time.current, mark.seen_at
      assert_equal Time.current, mark.arrived_at
    end
    arrive(record: create_media_asset)
    assert_equal "Media::Asset", Presence::Mark.order(:id).last.record_type
  end

  test "arriving twice from one tab is one row and keeps the first arrival; the second is the newer seen_at and here again" do
    travel_to Time.zone.local(2026, 10, 10, 12, 0, 0) do
      arrive
      Presence::Mark.report(user: @user, record: @page, tab: @tab, state: "away")
    end
    travel_to Time.zone.local(2026, 10, 10, 12, 0, 20) do
      arrive
    end
    mark = Presence::Mark.sole
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

  test "arriving is one statement" do
    assert_equal 1, capture_sql { arrive }.size
  end

  test "report changes the state and says whether it changed" do
    arrive
    assert Presence::Mark.report(user: @user, record: @page, tab: @tab, state: "away")
    assert_equal "away", Presence::Mark.sole.state
    assert_not Presence::Mark.report(user: @user, record: @page, tab: @tab, state: "away")
    assert Presence::Mark.report(user: @user, record: @page, tab: @tab, state: "here")
  end

  test "report moves seen_at with a change and leaves an unchanged row to beat" do
    travel_to(2.minutes.ago) { arrive }
    old = Presence::Mark.sole.seen_at
    assert_not Presence::Mark.report(user: @user, record: @page, tab: @tab, state: "here")
    assert_equal old, Presence::Mark.sole.seen_at
    assert Presence::Mark.report(user: @user, record: @page, tab: @tab, state: "away")
    assert_operator Presence::Mark.sole.seen_at, :>, old
  end

  test "report ignores a state that is not known, and a row that is not there" do
    arrive
    [ "gone", "", nil, "HERE", :away, 3 ].each do |state|
      assert_not Presence::Mark.report(user: @user, record: @page, tab: @tab, state:), state.inspect
    end
    assert_equal "here", Presence::Mark.sole.state
    assert_not Presence::Mark.report(user: @user, record: @page, tab: "tab-cccccccc", state: "away")
  end

  test "report and beat and leave are one statement each" do
    arrive
    assert_equal 1, capture_sql { Presence::Mark.report(user: @user, record: @page, tab: @tab, state: "away") }.size
    assert_equal 1, capture_sql { Presence::Mark.beat(user: @user, record: @page, tab: @tab) }.size
    assert_equal 1, capture_sql { Presence::Mark.leave(user: @user, record: @page, tab: @tab) }.size
  end

  test "beat moves seen_at and answers false for a row that is not there" do
    travel_to(30.seconds.ago) { arrive }
    old = Presence::Mark.sole.seen_at
    assert Presence::Mark.beat(user: @user, record: @page, tab: @tab)
    assert_operator Presence::Mark.sole.seen_at, :>, old
    assert_not Presence::Mark.beat(user: @user, record: @page, tab: "tab-cccccccc")
    assert_not Presence::Mark.beat(user: users(:one), record: @page, tab: @tab)
  end

  test "leave deletes only that tab's row" do
    arrive
    arrive(tab: "tab-bbbbbbbb")
    Presence::Mark.leave(user: @user, record: @page, tab: @tab)
    assert_equal [ "tab-bbbbbbbb" ], Presence::Mark.pluck(:tab)
  end

  test "fresh is the last 60 seconds" do
    arrive
    Presence::Mark.update_all(seen_at: 61.seconds.ago) # version: none (a test of presence)
    assert_empty Presence::Mark.fresh
    Presence::Mark.update_all(seen_at: 59.seconds.ago) # version: none (a test of presence)
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
    arrive
    Presence::Mark.report(user: @user, record: @page, tab: @tab, state: "away")
    Presence::Mark.beat(user: @user, record: @page, tab: @tab)
    Presence::Mark.leave(user: @user, record: @page, tab: @tab)
    assert_equal updated_at, @page.reload.updated_at
    assert_equal version, PublicSite::Version.current
    assert_equal events, Audit::Event.count
  end
end
