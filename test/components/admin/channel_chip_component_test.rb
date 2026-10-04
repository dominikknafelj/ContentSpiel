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

  test "a channel the audit log doesn't know is refused" do
    assert_raises(ArgumentError) { Admin::ChannelChipComponent.new(channel: "ftp") }
  end
end
