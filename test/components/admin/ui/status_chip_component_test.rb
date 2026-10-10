require "test_helper"

class Admin::Ui::StatusChipComponentTest < ViewComponent::TestCase
  test "each status is an outlined chip with a dot and its name" do
    { "live" => "bg-ok", "draft" => "bg-meta", "scheduled" => "bg-warn" }.each do |status, dot|
      render_inline(Admin::Ui::StatusChipComponent.new(status: status))
      assert_selector ".admin-status-chip.border-line-strong[data-status='#{status}']", text: status.humanize
      assert_selector ".admin-status-chip span.#{dot}[aria-hidden=true]"
    end
  end

  test "lists and the tree hide Live" do
    render_inline(Admin::Ui::StatusChipComponent.new(status: "live", hide_live: true))
    assert_no_selector ".admin-status-chip"
    render_inline(Admin::Ui::StatusChipComponent.new(status: "draft", hide_live: true))
    assert_selector ".admin-status-chip", text: "Draft"
  end

  test "a scheduled chip's tooltip is the scheduled time" do
    render_inline(Admin::Ui::StatusChipComponent.new(status: "scheduled", at: Time.zone.local(2026, 10, 5, 9, 30)))
    assert_selector ".admin-status-chip[title='5 Oct 2026, 09:30']"
  end

  test "an unknown status is a programming error" do
    assert_raises(ArgumentError) { Admin::Ui::StatusChipComponent.new(status: "archived") }
  end
end
