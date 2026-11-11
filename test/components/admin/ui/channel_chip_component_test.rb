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

  # The chip's classes as its own template spelled them before it drew
  # through `BadgeComponent`. The badge adds `gap-1` alone, a gap between
  # flex items, of which the chip has one (its word): nothing moves.
  BEFORE = {
    "mcp" => "admin-channel-chip inline-flex shrink-0 items-center rounded-cs px-1.5 py-px text-label bg-accent-tint text-accent",
    "admin" => "admin-channel-chip inline-flex shrink-0 items-center rounded-cs px-1.5 py-px text-label bg-sunken text-meta"
  }.freeze

  test "drawn as a compact badge, its classes are the ones it had, but the badge's inert gap" do
    BEFORE.each do |channel, before|
      render_inline(Admin::Ui::ChannelChipComponent.new(channel: channel))
      chip = page.find(".admin-channel-chip")

      assert_equal (before.split + %w[gap-1]).sort, chip[:class].split.sort, channel
      assert_equal 1, chip.native.children.size, "#{channel}: one child, so the gap draws nothing"
      assert_equal "span", chip.tag_name
    end
  end

  test "no channel draws nothing" do
    render_inline(Admin::Ui::ChannelChipComponent.new(channel: nil))
    assert_no_selector ".admin-channel-chip"
  end
end
