require "test_helper"

class Admin::Ui::StatusChipComponentTest < ViewComponent::TestCase
  test "Live is a solid live chip with its dot and the word" do
    render_inline(Admin::Ui::StatusChipComponent.new(status: "live"))
    assert_selector ".admin-status-chip.rounded-cs.bg-live.text-on-live.font-semibold[data-status=live]", text: "Live"
    assert_selector ".admin-status-chip span.bg-on-live[aria-hidden=true]"
  end

  test "Draft is an outlined chip with its ring and the word" do
    render_inline(Admin::Ui::StatusChipComponent.new(status: "draft"))
    assert_selector ".admin-status-chip.rounded-cs.border.border-field-line.bg-transparent.text-dim[data-status=draft]", text: "Draft"
    assert_selector ".admin-status-chip span[aria-hidden=true]", text: "○"
    assert_no_selector ".admin-status-chip.bg-live, .admin-status-chip.bg-scheduled"
  end

  test "Scheduled is the scheduled block with the word and the exact time as its title" do
    render_inline(Admin::Ui::StatusChipComponent.new(status: "scheduled", at: Time.zone.local(2026, 10, 5, 9, 30)))
    assert_selector ".admin-status-chip.rounded-cs.bg-scheduled.text-on-scheduled[data-status=scheduled][title='5 Oct 2026, 09:30']", text: "Scheduled"
  end

  test "every state says its word; the glyph is hidden from a screen reader" do
    { "live" => "Live", "draft" => "Draft", "scheduled" => "Scheduled" }.each do |status, word|
      render_inline(Admin::Ui::StatusChipComponent.new(status: status))
      assert_selector ".admin-status-chip[data-status='#{status}']", text: word
      assert_no_selector ".admin-status-chip span:not([aria-hidden=true])"
      assert_equal word, page.find(".admin-status-chip").text.delete("○").strip
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
