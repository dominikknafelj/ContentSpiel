module Admin
  module Ui
    # `Admin::Ui::ChannelChipComponent`: MCP in accent, the other channels in
    # meta, and a channel it does not know, drawn as its value.
    class ChannelChipComponentPreview < ViewComponent::Preview
      def admin = render(Admin::Ui::ChannelChipComponent.new(channel: "admin"))

      def mcp = render(Admin::Ui::ChannelChipComponent.new(channel: "mcp"))

      def setup = render(Admin::Ui::ChannelChipComponent.new(channel: "setup"))

      def console = render(Admin::Ui::ChannelChipComponent.new(channel: "console"))

      def system = render(Admin::Ui::ChannelChipComponent.new(channel: "system"))

      def unknown = render(Admin::Ui::ChannelChipComponent.new(channel: "public"))
    end
  end
end
