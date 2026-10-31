module Admin
  module SettingsScreen
    # The answer to a test mail, in place under the button (design answers M1
    # and M2): "Test mail sent to <address>. Check your inbox." in the ok
    # alert, or the warn alert with the failure's sentence and the server's
    # line. One drawing for the two screens that send one: Settings' card
    # (`MailTestResultComponent`, whose foot it is the end of) and the setup
    # wizard's Mail step.
    class MailTestOutcomeComponent < Admin::AdminComponent
      def initialize(address:, sent: false, alert: nil, line: nil)
        @address = address
        @sent = sent
        @alert = alert
        @line = line
      end

      # The ok line is a status, the alert has its own role; nothing at all
      # when nothing was sent yet (the live region stays for the answer).
      def call
        tag.div(role: (@alert ? nil : "status"), class: "mt-2 empty:hidden") { result }
      end

      private

      def result
        if @alert
          render(MailAlertComponent.new(sentence: @alert, line: @line))
        elsif @sent
          tag.p(t(".sent", address: @address), class: "rounded-cs bg-ok-tint px-3 py-2.5 text-[13px] leading-normal text-ok-ink")
        end
      end
    end
  end
end
