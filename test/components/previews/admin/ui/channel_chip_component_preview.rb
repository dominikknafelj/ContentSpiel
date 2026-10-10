module Admin
  module Ui
    # `Admin::Ui::ChannelChipComponent` (design pass round 3): MCP in accent, the
    # other four channels in meta.
    class ChannelChipComponentPreview < ViewComponent::Preview
      def admin = render(Admin::Ui::ChannelChipComponent.new(channel: "admin"))

      def mcp = render(Admin::Ui::ChannelChipComponent.new(channel: "mcp"))

      def setup = render(Admin::Ui::ChannelChipComponent.new(channel: "setup"))

      def console = render(Admin::Ui::ChannelChipComponent.new(channel: "console"))

      def system = render(Admin::Ui::ChannelChipComponent.new(channel: "system"))
    end
  end
end
