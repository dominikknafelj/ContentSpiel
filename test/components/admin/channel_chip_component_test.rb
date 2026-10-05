require "test_helper"

class Admin::ChannelChipComponentTest < ViewComponent::TestCase
  test "each channel is its uppercase word with an aria-label" do
    { "admin" => "ADMIN", "mcp" => "MCP", "setup" => "SETUP", "console" => "CONSOLE", "system" => "SYSTEM" }.each do |channel, word|
      render_inline(Admin::ChannelChipComponent.new(channel: channel))
      assert_selector ".admin-channel-chip[data-channel='#{channel}'][aria-label]", text: word
    end
  end

  test "MCP is the accent chip and the others are meta" do
    render_inline(Admin::ChannelChipComponent.new(channel: "mcp"))
    assert_selector ".admin-channel-chip.text-accent"
    render_inline(Admin::ChannelChipComponent.new(channel: "admin"))
    assert_selector ".admin-channel-chip.text-meta"
    assert_no_selector ".admin-channel-chip.text-accent"
  end

  test "an unknown channel is a meta chip with its upcased value, never an error" do
    render_inline(Admin::ChannelChipComponent.new(channel: "public"))
    assert_selector ".admin-channel-chip.text-meta", text: "PUBLIC"
  end

  test "no channel draws nothing" do
    render_inline(Admin::ChannelChipComponent.new(channel: nil))
    assert_no_selector ".admin-channel-chip"
  end
end
