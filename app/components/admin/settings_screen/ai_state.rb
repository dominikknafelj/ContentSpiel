module Admin
  module SettingsScreen
    # The one place that names AI translation's state and maps a test's
    # result to one, read by the key's chip and Test connection's result, so
    # both say the same word in the same tone.
    #
    # Without a provider AI translation is off, whatever key is stored or a
    # test answered; with one and no key it is No key, whatever a test
    # answered. Only with both does Test connection's result on this visit
    # (`:connected` or `:failed`) say Connected or Not connected, and until a
    # test the state is Key saved. Nothing of a test is stored.
    module AiState
      STATES = %i[off no_key key_saved connected not_connected].freeze
      TONES = { off: :off, no_key: :warn, key_saved: :ok, connected: :ok, not_connected: :danger }.freeze
      RESULTS = { connected: :connected, failed: :not_connected }.freeze

      def self.of(site_setting, result: nil)
        of_result(result) if result # an unknown result is refused in every state
        return :off if site_setting.ai_provider.blank?
        return :no_key unless site_setting.ai_api_key_set?

        result ? of_result(result) : :key_saved
      end

      # A Test connection's result (`:connected` or `:failed`) as its state.
      def self.of_result(result)
        raise ArgumentError, "unknown AI test result #{result.inspect}" unless RESULTS.key?(result)

        RESULTS.fetch(result)
      end

      def self.tone(state) = TONES.fetch(state)

      def self.word(state) = I18n.t(state, scope: "admin.components.settings_screen.ai_state", raise: true)
    end
  end
end
