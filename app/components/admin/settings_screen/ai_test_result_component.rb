module Admin
  module SettingsScreen
    # Where Test connection reports back, inline under the button (handoff
    # §4.5): "● CONNECTED · 412 MS" in ok ink and mono, or the provider's own
    # message in danger ink. Always renders its slot (`#settings-ai-test-result`)
    # -- empty until a test ran -- because the Turbo Stream answer of
    # `Admin::SettingsController#test_ai_connection` replaces exactly that
    # element. Neither form ever carries the API key: the message is the
    # provider's `AI::Error` text, written to be shown to an editor.
    class AiTestResultComponent < Admin::AdminComponent
      ID = "settings-ai-test-result".freeze

      # `milliseconds:` is the provider call's elapsed time measured on the
      # server; `message:` the failure. Neither given: the empty slot.
      def initialize(milliseconds: nil, message: nil)
        @milliseconds = milliseconds
        @message = message
      end

      def connected? = !milliseconds.nil?

      def label = "● CONNECTED · #{milliseconds} MS"

      def call
        tag.div(id: ID, role: "status", class: "mt-2 text-sm") do
          if connected?
            tag.span(label, class: "font-cs-mono text-label tracking-wide text-ok-ink")
          elsif message.present?
            tag.span(message, class: "text-danger-ink")
          end
        end
      end

      private

      attr_reader :milliseconds, :message
    end
  end
end
