module Admin
  # The door a change came through (design pass round 3, spec §5.4): ADMIN,
  # MCP, SETUP, CONSOLE or SYSTEM, in the audit log's rows and beside a
  # token-made change in the dashboard feed. MCP is the accent one (it is the
  # channel a person didn't type on, so it stands out); the rest are meta.
  # Colour is never the only cue: the word is the chip, and `aria-label`
  # spells the channel for a screen reader.
  class ChannelChipComponent < AdminComponent
    CHANNELS = %w[admin mcp setup console system].freeze

    def initialize(channel:)
      channel = channel.to_s
      raise ArgumentError, "unknown channel #{channel.inspect}" unless CHANNELS.include?(channel)

      @channel = channel
    end

    def label = channel.upcase

    def aria_label = "Channel: #{channel == "mcp" ? "MCP" : channel}"

    def tone_class
      channel == "mcp" ? "border-accent bg-accent-tint text-accent" : "border-line-strong text-meta"
    end

    private

    attr_reader :channel
  end
end
