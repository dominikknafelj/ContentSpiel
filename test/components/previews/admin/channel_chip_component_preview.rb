module Admin
  # `Admin::ChannelChipComponent` (design pass round 3): MCP in accent, the
  # other four channels in meta.
  class ChannelChipComponentPreview < ViewComponent::Preview
    def admin = render(Admin::ChannelChipComponent.new(channel: "admin"))

    def mcp = render(Admin::ChannelChipComponent.new(channel: "mcp"))

    def setup = render(Admin::ChannelChipComponent.new(channel: "setup"))

    def console = render(Admin::ChannelChipComponent.new(channel: "console"))

    def system = render(Admin::ChannelChipComponent.new(channel: "system"))
  end
end
