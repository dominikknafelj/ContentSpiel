module Admin
  module Ui
    # `Admin::Ui::MailFailedNoticeComponent` in its one state, a send that
    # failed. It reads only the state, the failure and its time, so the
    # preview hands over those three rather than writing the site's mail
    # columns.
    class MailFailedNoticeComponentPreview < ViewComponent::Preview
      FailedMail = Data.define(:state, :failed_at, :failure)

      def rest
        render Admin::Ui::MailFailedNoticeComponent.new(href: "#",
          mail_settings: FailedMail.new(state: :failed, failed_at: 2.hours.ago, failure: { "key" => "login", "line" => "535 5.7.8 Authentication failed" }))
      end
    end
  end
end
