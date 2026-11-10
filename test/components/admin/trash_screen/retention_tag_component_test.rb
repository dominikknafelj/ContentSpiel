require "test_helper"

# The retention tag counts CALENDAR days in the zone the request runs in,
# reads Today on the last day and when the sweep is overdue, Never at
# retention 0, and keeps the exact date as text as well as a tooltip.
class Admin::TrashScreen::RetentionTagComponentTest < ViewComponent::TestCase
  setup { @trashed = Time.zone.local(2026, 10, 1, 23, 30) }

  test "counts days to the due date" do
    travel_to Time.zone.local(2026, 10, 2, 8, 0) do
      render_inline tag(30)
      assert_selector "[data-retention]", text: "In 29 days"
    end
  end

  test "today and tomorrow are words in warn ink, a later day In N days in meta, and never is Never" do
    travel_to Time.zone.local(2026, 10, 29, 9, 0) do # due 31 Oct: two days to go
      render_inline tag(30)
      assert_selector "[data-retention].text-label.text-meta", text: "In 2 days"
      assert_no_selector "[data-retention].text-warn-ink"
    end
    travel_to Time.zone.local(2026, 10, 30, 0, 5) do # one calendar day to go though under 24 h
      render_inline tag(30)
      assert_selector "[data-retention].text-label.text-warn-ink", text: "Tomorrow"
      assert_no_selector "[data-retention].text-meta"
    end
    travel_to Time.zone.local(2026, 10, 31, 0, 5) do # due today, though the exact moment is 23:30 tonight
      render_inline tag(30)
      assert_selector "[data-retention].text-label.text-warn-ink", text: "Today"
    end
    travel_to Time.zone.local(2026, 12, 25, 9, 0) do # overdue: the sweep has not reached it yet
      render_inline tag(30)
      assert_selector "[data-retention].text-warn-ink", text: "Today"
      assert_no_text "-"
    end
    render_inline tag(0)
    assert_selector "[data-retention].text-label.text-meta", text: "Never"
  end

  test "is read in the site zone" do
    Time.use_zone("Pacific/Auckland") do # 23:30 UTC on 1 Oct is 12:30 on 2 Oct there
      trashed = Time.utc(2026, 10, 1, 23, 30)
      travel_to Time.utc(2026, 10, 31, 12, 0) do # 1 Nov 01:00 in Auckland: past 2 Oct + 30 d = 1 Nov? due 1 Nov => today
        render_inline Admin::TrashScreen::RetentionTagComponent.new(trashed_at: trashed, retention_days: 30)
        assert_selector "[data-retention]", text: "Today"
        assert_selector "[data-retention][title='Deleted for good on or after 1 Nov 2026']"
      end
    end
  end

  test "Never at retention 0, and the date is also screen-reader text, never danger" do
    render_inline tag(0)
    assert_selector "[data-retention]", text: "Never"
    assert_selector "[data-retention][title='Kept until someone deletes it for good']"

    render_inline tag(30)
    assert_selector "[data-retention] .sr-only", text: "Deleted for good on or after 31 Oct 2026", visible: :all
    assert_no_selector "[data-retention][class*=danger]"
    assert_selector "[data-retention].text-label"
  end

  private

  def tag(days) = Admin::TrashScreen::RetentionTagComponent.new(trashed_at: @trashed, retention_days: days)
end
