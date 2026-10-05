module Admin
  # The door a change came through (design pass round 3, spec §5.4): ADMIN,
  # MCP, SETUP, CONSOLE or SYSTEM, in the audit log's rows and beside a
  # token-made change in the dashboard feed. MCP is the accent one (it is the
  # channel a person didn't type on, so it stands out); the rest are meta.
  # Colour is never the only cue: the word is the chip, and `aria-label`
  # spells the channel for a screen reader.
  class ChannelChipComponent < AdminComponent
    CHANNELS = %w[admin mcp setup console system].freeze

    # Never raises on data: `audit_events.channel` can be nil (no channel) or
    # a value this list doesn't know ("public", a plugin's), and the dashboard
    # and audit log pass every row through here. nil draws nothing; an unknown
    # string draws a meta chip with its upcased value.
    def initialize(channel:)
      @channel = channel.to_s
    end

    def render? = channel.present?

    def label = channel.upcase

    def aria_label = "Channel: #{channel == "mcp" ? "MCP" : channel.downcase}"

    def tone_class
      channel == "mcp" ? "border-accent bg-accent-tint text-accent" : "border-line-strong text-meta"
    end

    private

    attr_reader :channel
  end
end
