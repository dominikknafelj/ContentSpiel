module Admin
  module SettingsScreen
    # Where Test connection reports back, inline under the button: AiState's
    # Connected chip with the provider call's time, or Not connected with the
    # provider's own message under it in danger ink. Always renders its slot
    # (`#settings-ai-test-result`) -- empty until a test ran -- because the
    # Turbo Stream answer of `Admin::SettingsController#test_ai_connection`
    # replaces exactly that element. Neither form ever carries the API key:
    # the message is the provider's `AI::Error` text, written to be shown to
    # an editor.
    class AiTestResultComponent < Admin::AdminComponent
      ID = "settings-ai-test-result".freeze

      # `milliseconds:` is the provider call's elapsed time measured on the
      # server; `message:` the failure. Neither given: the empty slot.
      def initialize(milliseconds: nil, message: nil)
        @milliseconds = milliseconds
        @message = message
      end

      def connected? = !milliseconds.nil?

      def failed? = !connected? && message.present?

      def call
        tag.div(id: ID, role: "status", class: "mt-2 text-sm") do
          if connected?
            chip(:connected, detail: t(".time", milliseconds: milliseconds))
          elsif failed?
            safe_join([ chip(:not_connected), tag.p(message, class: "mt-1 text-danger-ink") ])
          end
        end
      end

      private

      attr_reader :milliseconds, :message

      def chip(state, detail: nil) = render(Admin::Ui::StateChipComponent.new(tone: AiState.tone(state), label: AiState.word(state), detail: detail))
    end
  end
end
