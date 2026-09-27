require "test_helper"

class Admin::StatusBadgeComponentTest < ViewComponent::TestCase
  test "renders the humanized status" do
    render_inline Admin::StatusBadgeComponent.new(status: "draft")
    assert_text "Draft"

    render_inline Admin::StatusBadgeComponent.new(status: "live")
    assert_text "Live"
  end

  test "a scheduled badge shows its date on hover via a title attribute" do
    at = Time.zone.parse("2026-10-01 09:00")
    render_inline Admin::StatusBadgeComponent.new(status: "scheduled", at: at)

    assert_selector "[title]"
  end

  test "draft and live have no hover date" do
    render_inline Admin::StatusBadgeComponent.new(status: "draft")
    refute_selector "[title]"
  end

  test "rejects an unknown status" do
    assert_raises(ArgumentError) { Admin::StatusBadgeComponent.new(status: "archived") }
  end
end
