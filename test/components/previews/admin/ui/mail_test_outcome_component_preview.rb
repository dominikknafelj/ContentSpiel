module Admin
  module Ui
    # `Admin::Ui::MailTestOutcomeComponent`: nothing sent yet, a sent test
    # mail, and a failed one with the server's line.
    class MailTestOutcomeComponentPreview < ViewComponent::Preview
      def rest = render(Admin::Ui::MailTestOutcomeComponent.new(address: "ada@example.com"))

      def sent = render(Admin::Ui::MailTestOutcomeComponent.new(address: "ada@example.com", sent: true))

      def failed
        render(Admin::Ui::MailTestOutcomeComponent.new(address: "ada@example.com", alert: "The server refused the login.", line: "535 5.7.8 Authentication failed"))
      end
    end
  end
end
