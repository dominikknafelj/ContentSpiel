require "test_helper"

class Admin::Ui::ScheduledDateComponentTest < ViewComponent::TestCase
  test "a scheduled date is an amber block with its month and day, hidden from a screen reader" do
    render_inline Admin::Ui::ScheduledDateComponent.new(at: Time.zone.local(2030, 3, 7, 9, 30))

    assert_selector "span.admin-scheduled-date.bg-scheduled.text-on-scheduled.rounded-chip.size-10[aria-hidden=true]", count: 1
    assert_selector ".admin-scheduled-date > span.text-label", exact_text: "Mar"
    assert_selector ".admin-scheduled-date > span.text-h2.font-semibold", exact_text: "7"
    assert_selector ".admin-scheduled-date > span", count: 2
    assert_no_selector "[class*='font-cs-mono'], [class*='uppercase']"
  end

  test "the block reads the date in the site time zone" do
    Time.use_zone("Europe/Berlin") { render_inline Admin::Ui::ScheduledDateComponent.new(at: Time.utc(2030, 6, 30, 23, 30)) }

    assert_selector ".admin-scheduled-date > span.text-label", exact_text: "Jul"
    assert_selector ".admin-scheduled-date > span.text-h2", exact_text: "1"
  end
end
