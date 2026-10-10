require "test_helper"

class Admin::Ui::TimeAgoComponentTest < ViewComponent::TestCase
  include ActiveSupport::Testing::TimeHelpers

  test "recent times read as short relative phrases with the absolute time as tooltip" do
    travel_to Time.zone.local(2026, 10, 3, 14, 0) do
      {
        20.seconds.ago => "just now", 5.minutes.ago => "5m ago", 2.hours.ago => "2h ago",
        Time.zone.local(2026, 10, 2, 9, 0) => "yesterday", 3.days.ago => "3d ago",
        Time.zone.local(2026, 9, 1, 9, 0) => "1 Sep", Time.zone.local(2025, 9, 1, 9, 0) => "1 Sep 2025"
      }.each do |time, text|
        render_inline(Admin::Ui::TimeAgoComponent.new(time: time))
        assert_selector "time[datetime='#{time.iso8601}']", exact_text: text
      end
      render_inline(Admin::Ui::TimeAgoComponent.new(time: 2.hours.ago))
      assert_selector "time[title='3 Oct 2026, 12:00']"
    end
  end

  test "the previous calendar day is yesterday even within 24 hours, and earlier today stays hours" do
    travel_to Time.zone.local(2026, 10, 3, 0, 10) do
      render_inline(Admin::Ui::TimeAgoComponent.new(time: Time.zone.local(2026, 10, 2, 23, 50)))
      assert_selector "time", exact_text: "yesterday"
    end
    travel_to Time.zone.local(2026, 10, 3, 14, 0) do
      render_inline(Admin::Ui::TimeAgoComponent.new(time: Time.zone.local(2026, 10, 3, 0, 5)))
      assert_selector "time", exact_text: "13h ago"
    end
  end

  test "Nd ago counts calendar days, like yesterday does" do
    travel_to Time.zone.local(2026, 10, 3, 14, 0) do
      render_inline(Admin::Ui::TimeAgoComponent.new(time: 47.hours.ago)) # Oct 1, 15:00: two calendar days back
      assert_selector "time", exact_text: "2d ago"
    end
  end

  test "a future time in another year names the year" do
    travel_to Time.zone.local(2026, 10, 3, 14, 0) do
      render_inline(Admin::Ui::TimeAgoComponent.new(time: Time.zone.local(2027, 1, 5, 9, 30)))
      assert_selector "time", exact_text: "5 Jan 2027, 09:30"
    end
  end

  test "days are the site zone's, not UTC's" do
    travel_to Time.utc(2026, 10, 3, 22, 30) do
      Time.use_zone("Europe/Berlin") do # 00:30 on the 4th
        render_inline(Admin::Ui::TimeAgoComponent.new(time: Time.utc(2026, 10, 3, 21, 0))) # 23:00 on the 3rd
        assert_selector "time", exact_text: "yesterday"
      end
    end
  end

  test "a future time reads as an absolute date, and nil renders nothing" do
    travel_to Time.zone.local(2026, 10, 3, 14, 0) do
      render_inline(Admin::Ui::TimeAgoComponent.new(time: Time.zone.local(2026, 10, 5, 9, 30)))
      assert_selector "time", exact_text: "5 Oct, 09:30"
    end
    render_inline(Admin::Ui::TimeAgoComponent.new(time: nil))
    assert_no_selector "time"
  end

  test "title: replaces the tooltip" do
    render_inline Admin::Ui::TimeAgoComponent.new(time: 2.hours.ago, title: "4 Oct 2026, 09:00 – 09:40")

    assert_selector "time[title='4 Oct 2026, 09:00 – 09:40']"
  end
end
