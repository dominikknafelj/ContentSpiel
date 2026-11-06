require "test_helper"

class Admin::Ui::ChannelChipComponentTest < ViewComponent::TestCase
  test "each channel is its word, MCP in capitals with an aria-label" do
    { "admin" => "Admin", "mcp" => "MCP", "setup" => "Setup", "console" => "Console", "system" => "System" }.each do |channel, word|
      render_inline(Admin::Ui::ChannelChipComponent.new(channel: channel))
      assert_selector ".admin-channel-chip[data-channel='#{channel}'][aria-label]", text: word
    end
  end

  test "MCP is the accent chip and the others are meta" do
    render_inline(Admin::Ui::ChannelChipComponent.new(channel: "mcp"))
    assert_selector ".admin-channel-chip.text-accent"
    render_inline(Admin::Ui::ChannelChipComponent.new(channel: "admin"))
    assert_selector ".admin-channel-chip.text-meta"
    assert_selector ".admin-channel-chip.bg-sunken:not([class*=border])"
    assert_no_selector ".admin-channel-chip.text-accent"
  end

  test "an unknown channel is a meta chip with its value, never an error" do
    render_inline(Admin::Ui::ChannelChipComponent.new(channel: "public"))
    assert_selector ".admin-channel-chip.text-meta", text: "Public"
  end

  test "no channel draws nothing" do
    render_inline(Admin::Ui::ChannelChipComponent.new(channel: nil))
    assert_no_selector ".admin-channel-chip"
  end
end
