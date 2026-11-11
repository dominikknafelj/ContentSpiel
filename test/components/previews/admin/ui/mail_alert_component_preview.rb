module Admin
  module Ui
    # `Admin::Ui::MailAlertComponent`: a mail failure's sentence, and with the
    # server's reply line under it.
    class MailAlertComponentPreview < ViewComponent::Preview
      def rest = render(Admin::Ui::MailAlertComponent.new(sentence: "The server refused the login."))

      def with_line = render(Admin::Ui::MailAlertComponent.new(sentence: "The server refused the login.", line: "535 5.7.8 Authentication failed"))
    end
  end
end
