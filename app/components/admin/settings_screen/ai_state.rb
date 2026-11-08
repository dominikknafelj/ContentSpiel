module Admin
  module SettingsScreen
    # The one place that names AI translation's state, read by the key's
    # chip, Test connection's result and the rail's AI row, so the three say
    # the same word in the same tone.
    #
    # Without a provider AI translation is off, whatever key is stored. With
    # one, the state is whether a key is stored, until Test connection has
    # run on this visit: its result (`:connected` or `:failed`) then says
    # Connected or Not connected. Nothing of a test is stored.
    module AiState
      STATES = %i[off no_key key_saved connected not_connected].freeze
      TONES = { off: :off, no_key: :warn, key_saved: :ok, connected: :ok, not_connected: :danger }.freeze
      RESULTS = { connected: :connected, failed: :not_connected }.freeze

      def self.of(site_setting, result: nil)
        if result
          raise ArgumentError, "unknown AI test result #{result.inspect}" unless RESULTS.key?(result)

          return RESULTS.fetch(result)
        end
        return :off if site_setting.ai_provider.blank?

        site_setting.ai_api_key_set? ? :key_saved : :no_key
      end

      def self.tone(state) = TONES.fetch(state)

      def self.word(state) = I18n.t(state, scope: "admin.components.settings_screen.ai_state", raise: true)
    end
  end
end
