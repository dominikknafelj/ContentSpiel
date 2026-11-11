module Admin
  module Ui
    # `Admin::Ui::MailHostValueComponent`: a mail field the host sets, with its
    # value, and a half of the login, whose box is the mask. The preview reads
    # the settings of a given environment, never the site's own.
    class MailHostValueComponentPreview < ViewComponent::Preview
      def rest
        render Admin::Ui::MailHostValueComponent.new(field: :server, label: "Server", mail_settings: MailSettings.current(SiteSetting.instance, env: { "MAIL_SMTP_SERVER" => "smtp.host.example" }))
      end

      def masked
        render Admin::Ui::MailHostValueComponent.new(field: :password, label: "Password", mail_settings: MailSettings.current(SiteSetting.instance, env: { "MAIL_SMTP_PASSWORD" => "not-shown" }))
      end
    end
  end
end
