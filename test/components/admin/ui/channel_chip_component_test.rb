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

  # The chip is the one badge, at the badge's one height (2px above and
  # below the label; the audit log's 20px line holds it), with its hook.
  test "drawn as a badge: the badge's classes, its tone, and the chip's hook" do
    { "mcp" => :accent, "admin" => :neutral }.each do |channel, tone|
      render_inline(Admin::Ui::ChannelChipComponent.new(channel: channel))
      chip = page.find(".admin-channel-chip")

      expected = [ Admin::Ui::BadgeComponent::CLASS, Admin::Ui::BadgeComponent::TONES.fetch(tone), "admin-channel-chip" ].join(" ").split
      assert_equal expected.sort, chip[:class].split.sort, channel
      assert_includes chip[:class].split, "py-0.5", channel
      assert_equal "span", chip.tag_name
    end
  end

  test "no channel draws nothing" do
    render_inline(Admin::Ui::ChannelChipComponent.new(channel: nil))
    assert_no_selector ".admin-channel-chip"
  end
end
