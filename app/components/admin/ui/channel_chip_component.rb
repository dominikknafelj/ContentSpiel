module Admin
  module Ui
    # The door a change came through: Admin,
    # MCP, Setup, Console or System, in the audit log's rows and beside a
    # token-made change in the dashboard feed. MCP is the accent one (it is the
    # channel a person didn't type on, so it stands out); the rest are meta.
    # Colour is never the only cue: the word is the chip, and `aria-label`
    # spells the channel for a screen reader.
    class ChannelChipComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Inline text named by its aria-label (Channel: and the channel), with no role of its own; it takes no focus.",
        motion: :none,
        content_edges: %i[short missing],
        widths: :fluid,
        interface: %i[channel],
        limits: [
          "A nil channel draws nothing, and an unknown one draws a meta chip with its stored value.",
          "Its words (the channel's name, MCP and the Channel: label) are English in the code, not keys."
        ],
        states: %i[admin mcp setup console system unknown],
        keys: [],
        slots: [],
        controller: nil
      )

      CHANNELS = %w[admin mcp setup console system].freeze

      # Never raises on data: `audit_events.channel` can be nil (no channel) or
      # a value this list doesn't know ("public", a plugin's), and the dashboard
      # and audit log pass every row through here. nil draws nothing; an unknown
      # string draws a meta chip with its value.
      def initialize(channel:)
        @channel = channel.to_s
      end

      def render? = channel.present?

      def label = channel == "mcp" ? "MCP" : channel.upcase_first

      def aria_label = "Channel: #{channel == "mcp" ? "MCP" : channel.downcase}"

      def tone_class
        channel == "mcp" ? "bg-accent-tint text-accent" : "bg-sunken text-meta"
      end

      private

      attr_reader :channel
    end
  end
end
