module Admin
  module SettingsScreen
    # `Admin::SettingsScreen::MailFieldsComponent`: the Mail form of Settings
    # and the wizard, its two groups, and a field the host sets.
    class MailFieldsComponentPreview < ViewComponent::Preview
      def default
        site = SiteSetting.instance
        render_fields(MailSettings.current(site), site)
      end

      def from_host
        site = SiteSetting.instance
        render_fields(MailSettings.current(site, env: { "MAIL_SMTP_SERVER" => "smtp.host.example", "MAIL_SMTP_SECURITY" => "tls" }), site)
      end

      private

      def render_fields(mail_settings, site)
        values = Admin::SettingsScreen::Values.new(site: site)
        render Admin::SettingsScreen::MailFieldsComponent.new(mail_settings: mail_settings, value: values.method(:mail), name_prefix: "site_setting",
          id_prefix: "preview-") do |fields|
          fields.with_login { ApplicationController.render(Admin::SettingsScreen::MailLoginComponent.new(site_setting: site, mail_settings: mail_settings), layout: false) }
        end
      end
    end
  end
end
