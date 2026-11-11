module Admin
  module SettingsScreen
    # The answer to a test mail, in place under the button: "Test mail sent
    # to <address>. Check your inbox." in the compact ok notice, or the warn
    # alert with the failure's sentence and the server's line. One drawing
    # for the two screens that send one: Settings' card
    # (`MailTestResultComponent`, whose foot it is the end of) and the setup
    # wizard's Mail step.
    class MailTestOutcomeComponent < Admin::AdminComponent
      def initialize(address:, sent: false, alert: nil, line: nil)
        @address = address
        @sent = sent
        @alert = alert
        @line = line
      end

      # The ok line's status is this region's, so its notice has no role of
      # its own and is heard once; the alert has its own role. Nothing at all
      # when nothing was sent yet (the live region stays for the answer).
      def call
        tag.div(role: (@alert ? nil : "status"), class: "mt-2 empty:hidden") { result }
      end

      private

      def result
        if @alert
          render(Admin::Ui::MailAlertComponent.new(sentence: @alert, line: @line))
        elsif @sent
          render(Admin::Ui::NoticeComponent.new(tone: :ok, size: :compact, role: nil).with_content(t(".sent", address: @address)))
        end
      end
    end
  end
end
