require "test_helper"

# A row of the History screen's versions (the StudioHistory card, "A version
# row"): the version, its chip, when it went or goes live, and who published
# it; the working version first, with its mark and when it was saved.
class Admin::HistoryScreen::VersionRowComponentTest < ViewComponent::TestCase
  include ContentHelper

  setup do
    @me = users(:one)
    @dana = users(:two).tap { |user| user.update!(name: "Dana Weiss") }
    @pricing = create_page(title: "Pricing")
  end

  def row_for(number)
    Publishing::History.new(@pricing.reload).rows.find { |row| row.number == number }
  end

  def draw(**options)
    as(@me) { render_inline Admin::HistoryScreen::VersionRowComponent.new(**options) }
  end

  test "a version's three lines: its name and chip, when it went live, and who published it" do
    went_live = Time.zone.parse("2026-11-12 09:00")
    Publishing::Version.of(@pricing).update_all(live_at: went_live, created_at: went_live, created_by_id: @dana.id) # version: none (a test) # changes: none (a test)
    @pricing.update_columns(published_at: went_live) # version: none (a test) # changes: none (a test)

    draw(row: row_for(1), href: "/v")

    assert_selector "li[data-version-row='1'] a.admin-row-link[href='/v']", text: "Version 1"
    assert_selector ".admin-status-chip", text: "Live"
    assert_text "Went live #{I18n.l(went_live.in_time_zone(Current.site.effective_time_zone), format: :"admin.datetime")}"
    assert_no_text "was scheduled"
    assert_text "Dana Weiss"
    assert_selector "[aria-hidden=true]", text: "DW"
    assert_no_selector "a[aria-current]"
  end

  test "the chosen row is the current one" do
    draw(row: row_for(1), href: "/v", current: true)

    assert_selector "a[aria-current=true]", text: "Version 1"
  end

  test "a first copy with no publisher was kept when history began; a later one's publisher was removed" do
    Publishing::Version.take!(@pricing.reload, by: @me) # version: none (a test takes a copy)
    Publishing::Version.of(@pricing).update_all(created_by_id: nil) # version: none (a test) # changes: none (a test)

    draw(row: row_for(1), href: "/v")
    assert_text "Kept when history began"

    draw(row: row_for(2), href: "/v")
    assert_text "Published by a removed account"
    assert_no_text "Kept when history began"
  end

  test "a scheduled record's copy goes live at the record's time, and once that has passed was scheduled" do
    at = 3.days.from_now.change(hour: 9, min: 0)
    @pricing.update_columns(published_at: at) # version: none (a test schedules a page) # changes: none (a test schedules a page)
    shown = I18n.l(at.in_time_zone(Current.site.effective_time_zone), format: :"admin.datetime")

    draw(row: row_for(1), href: "/v")

    assert_selector ".admin-status-chip[title]", text: "Scheduled"
    assert_equal at.to_i, row_for(1).at.to_i
    assert_text "Goes live #{shown}"
    assert_no_text "Went live"

    travel_to(4.days.from_now) { draw(row: row_for(1), href: "/v") }

    assert_text "Went live #{shown} · was scheduled"
  end

  test "a pending copy is Scheduled and goes live later; only a copy gone live says it was scheduled" do
    live_at = 3.days.from_now.change(hour: 9, min: 0)
    pending = Publishing::Version.take!(@pricing.reload, live_at: live_at, by: @me) # version: none (a test takes a copy)

    draw(row: row_for(pending.number), href: "/v")

    assert_selector ".admin-status-chip", text: "Scheduled"
    assert_text "Goes live #{I18n.l(live_at.in_time_zone(Current.site.effective_time_zone), format: :"admin.datetime")}"
    assert_no_text "was scheduled"

    Publishing::Version.where(id: pending.id).update_all(live_at: 1.hour.ago, created_at: 2.hours.ago) # version: none (a test lets the copy's time pass) # changes: none (a test)
    draw(row: row_for(pending.number), href: "/v")

    assert_text "· was scheduled"
  end

  test "an earlier copy has no chip" do
    Publishing::Version.take!(@pricing.reload, by: @me) # version: none (a test takes a copy)

    draw(row: row_for(1), href: "/v")

    assert_no_selector ".admin-status-chip"
  end

  test "the working version: its mark when set, and when it was saved, with no link" do
    assert Pages::Save.call(@pricing.reload, translations: { "en" => { title: "Prices" } }).ok?
    working = Publishing::History.new(@pricing.reload).working

    draw(working: working)

    assert_selector "li[data-version-row=working]", text: "Working version"
    assert_text "Unpublished changes"
    assert_text "Saved #{I18n.l(working.saved_at.in_time_zone(Current.site.effective_time_zone), format: :"admin.time")} today"
    assert_no_selector "a"
  end

  test "a working version with nothing unpublished carries no mark" do
    draw(working: Publishing::History.new(@pricing.reload).working)

    assert_no_text "Unpublished changes"
  end
end
