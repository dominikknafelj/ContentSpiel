require "test_helper"

# `Admin::DashboardScreen::RowComponent`: a record in "Pick up where you left
# off" (title, type dot, "edited 2h ago") or "Publishing on its own" (the
# scheduled date block, title, "in 5 days", "by you").
class Admin::DashboardScreen::RowComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }
  teardown { Current.reset }

  test "a draft post row links to its editor with its type dot and when it was edited" do
    post = create_post(title: "Half-written", published: false)

    render_inline Admin::DashboardScreen::RowComponent.new(record: post, variant: :draft)

    assert_selector "a[href='/cs-studio/posts/#{post.id}']", text: "Half-written"
    assert_selector ".admin-type-dot", text: "Blog"
    assert_text(/edited just now/)
    assert_selector "time"
    assert_no_selector ".admin-scheduled-date"
  end

  test "a row with no title reads (untitled)" do
    post = create_post(title: "x", published: false)
    post.update_columns(title: {})

    render_inline Admin::DashboardScreen::RowComponent.new(record: post.reload, variant: :draft)
    assert_selector "a", exact_text: "(untitled)"
  end

  # The dashboard shows dates in the SITE time zone. 23:30 UTC on 30 June is
  # already 1 July in Berlin; the block, the phrase's calendar day and the
  # tooltip must all say 1 July, 01:30.
  test "a going-live row's date block, phrase and tooltip use the site time zone, not UTC" do
    post = create_post(title: "Midnight", published: false)
    post.update_columns(published_at: Time.utc(2030, 6, 30, 23, 30))

    Time.use_zone("Europe/Berlin") do
      render_inline Admin::DashboardScreen::RowComponent.new(record: post, variant: :going_live)
    end
    assert_selector ".admin-scheduled-date span", exact_text: "Jul"
    assert_selector ".admin-scheduled-date span", exact_text: "1"
    assert_selector "time[title='1 Jul 2030, 01:30']"

    Time.use_zone("UTC") do
      render_inline Admin::DashboardScreen::RowComponent.new(record: post, variant: :going_live)
    end
    assert_selector "time[title='30 Jun 2030, 23:30']"
  end

  test "a draft page row says Page" do
    page = create_page(title: "About", published: false)

    render_inline Admin::DashboardScreen::RowComponent.new(record: page, variant: :draft)

    assert_selector "a[href='/cs-studio/pages/#{page.id}']", text: "About"
    assert_text "Page"
  end

  test "a going-live row draws the scheduled date block and says when in words" do
    travel_to Time.zone.local(2030, 1, 10, 12) do
      post = create_post(title: "Coming soon", published: false)
      post.update_columns(published_at: Time.zone.local(2030, 1, 15, 13))

      render_inline Admin::DashboardScreen::RowComponent.new(record: post, variant: :going_live, mine: true)
      assert_selector "span.admin-scheduled-date.bg-scheduled.text-on-scheduled[aria-hidden=true]", count: 1
      assert_selector ".admin-scheduled-date > span.text-label", exact_text: "Jan"
      assert_selector ".admin-scheduled-date > span.text-h2", exact_text: "15"
      assert_selector "time[datetime='#{post.published_at.iso8601}'][title='15 Jan 2030, 13:00']", exact_text: "in 5 days"
      assert_text "by you"
      assert_no_selector "[class*='warn']"

      render_inline Admin::DashboardScreen::RowComponent.new(record: post, variant: :going_live, mine: false)
      assert_no_text "by you"
    end
  end

  test "the phrase counts calendar days: an hour past midnight is tomorrow, later today is in hours" do
    travel_to Time.zone.local(2030, 1, 10, 23, 30) do
      post = create_post(title: "Just after midnight", published: false)
      post.update_columns(published_at: Time.zone.local(2030, 1, 11, 0, 30))
      render_inline Admin::DashboardScreen::RowComponent.new(record: post, variant: :going_live)
      assert_text "tomorrow"
    end

    travel_to Time.zone.local(2030, 1, 10, 9) do
      post = create_post(title: "This afternoon", published: false)
      post.update_columns(published_at: Time.zone.local(2030, 1, 10, 13, 30))
      render_inline Admin::DashboardScreen::RowComponent.new(record: post, variant: :going_live)
      assert_text "in 4h"
    end

    travel_to Time.zone.local(2030, 1, 10, 13) do
      post = create_post(title: "Within the hour", published: false)
      post.update_columns(published_at: Time.zone.local(2030, 1, 10, 13, 30))
      render_inline Admin::DashboardScreen::RowComponent.new(record: post, variant: :going_live)
      assert_text "soon"
    end

    travel_to Time.zone.local(2030, 1, 10, 9) do
      post = create_post(title: "In a day", published: false)
      post.update_columns(published_at: Time.zone.local(2030, 1, 12, 9))
      render_inline Admin::DashboardScreen::RowComponent.new(record: post, variant: :going_live)
      assert_text "in 2 days"
    end
  end

  test "an unknown variant is refused" do
    assert_raises(ArgumentError) { Admin::DashboardScreen::RowComponent.new(record: create_post(title: "x"), variant: :other) }
  end
end
