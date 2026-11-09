module Admin
  module SettingsScreen
    # The Mail card (docs/reference/mail.md), after AI translation, for
    # `settings.manage`.
    #
    # - The fields are `MailFieldsComponent`, the Mail form the wizard's Mail
    #   step draws too: Server (server, port, security, the login) and Sender
    #   (name, address), fields of the one Settings form saved with its save
    #   bar. The root carries `mail-port`, which puts a security's port into
    #   Port.
    # - The login, in the fields' `login` slot, is `MailLoginComponent`:
    #   instant forms, written once.
    # - The state (`MailStateComponent`) stands at the head's end.
    # - "Send test mail" is the foot (`MailTestResultComponent`).
    #
    # With every field from the host the card says so once, and only the test
    # button is left to press.
    #
    # `mail_settings` is the `MailSettings` of the stored row (what the state
    # and the host's fields are read from); `values` what the fields show
    # (typed beats stored after a refused save); `errors` the refused save's
    # `ActiveModel::Errors`, or nil.
    class MailCardComponent < Admin::AdminComponent
      def initialize(site_setting:, mail_settings:, values:, errors: nil)
        @site_setting = site_setting
        @mail_settings = mail_settings
        @values = values
        @errors = errors
      end

      def all_from_host? = mail_settings.all_from_host?

      def fields
        Admin::SettingsScreen::MailFieldsComponent.new(mail_settings: mail_settings, value: values.method(:mail), changed: values.method(:saved_change),
          name_prefix: "site_setting", id_prefix: "settings-", errors: errors)
      end

      # Where "Send test mail" sends: the person looking at the card.
      def address = Current.user&.email_address.to_s

      private

      attr_reader :site_setting, :mail_settings, :values, :errors
    end
  end
end
