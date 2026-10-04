require "test_helper"

# `Admin::DashboardScreen::RowComponent`: a record in "Your drafts" (title,
# type dot, "edited 2h ago") or "Going live next" (date tile, title, "in 5
# days", "by you").
class Admin::DashboardScreen::RowComponentTest < ViewComponent::TestCase
  setup { Current.actor = users(:one) }
  teardown { Current.reset }

  test "a draft post row links to its editor with its type dot and when it was edited" do
    post = create_post(title: "Half-written", published: false)

    render_inline Admin::DashboardScreen::RowComponent.new(record: post, variant: :draft)

    assert_selector "a[href='/cs-studio/posts/#{post.id}']", text: "Half-written"
    assert_selector ".admin-type-dot", text: "Blog"
    assert_text "edited"
    assert_selector "time"
  end

  # Final review C, I5: the dashboard shows dates in the SITE time zone.
  # 23:30 UTC on 30 June is already 1 July in Berlin; the tile, the phrase's
  # calendar day and the tooltip must all say 1 July, 01:30.
  test "a going-live row's tile, phrase and tooltip use the site time zone, not UTC" do
    post = create_post(title: "Midnight", published: false)
    post.update_columns(published_at: Time.utc(2030, 6, 30, 23, 30))

    Time.use_zone("Europe/Berlin") do
      render_inline Admin::DashboardScreen::RowComponent.new(record: post, variant: :going_live)
    end
    assert_selector "span", text: /\AJul\z/i
    assert_selector "span", text: "1"
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

  test "a going-live row has the date tile, a relative phrase and by you only when mine" do
    travel_to Time.zone.local(2030, 1, 10, 12) do
      post = create_post(title: "Coming soon", published: false)
      post.update_columns(published_at: Time.zone.local(2030, 1, 15, 13))

      render_inline Admin::DashboardScreen::RowComponent.new(record: post, variant: :going_live, mine: true)
      assert_selector "span.text-warn-ink", text: "Jan"
      assert_selector "span.text-\\[18px\\]", text: "15"
      assert_text "in 5 days"
      assert_text "by you"

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
  end

  test "an unknown variant is refused" do
    assert_raises(ArgumentError) { Admin::DashboardScreen::RowComponent.new(record: create_post(title: "x"), variant: :other) }
  end
end
