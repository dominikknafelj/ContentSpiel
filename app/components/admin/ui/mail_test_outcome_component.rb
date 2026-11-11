module Admin
  module Ui
    # The answer to a test mail, in place under the button: "Test mail sent
    # to <address>. Check your inbox." in the compact ok notice, or the warn
    # alert with the failure's sentence and the server's line. One drawing
    # for the two screens that send one: Settings' card
    # (`Admin::SettingsScreen::MailTestResultComponent`, whose foot it is the end of) and the setup
    # wizard's Mail step.
    class MailTestOutcomeComponent < Admin::AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A live region (role=status) that holds the answer: the ok line is heard through it, once, and the failure is an alert of its own role; with nothing sent it is empty and hidden, and stays for the answer.",
        motion: :none,
        content_edges: %i[none long],
        widths: :from_container,
        interface: %i[address sent alert line],
        limits: [
          "It only draws an answer: the sending, the limit and the sentence are MailTestSending's and MailFailure's.",
          "The ok line's notice has no role of its own, so it is heard once, as the region's status."
        ],
        states: %i[rest sent failed],
        keys: %w[sent],
        slots: [],
        controller: nil,
        keyboard: "It takes no focus: the answer under the Send test mail button is words in a notice, with no link or control of its own; the button, which the keyboard stops on, is the card's and the wizard's."
      )

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
