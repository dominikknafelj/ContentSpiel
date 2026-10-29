module Admin
  module SettingsScreen
    # The Mail card (spec "Settings → Mail", design answers M2 and M3; docs/
    # reference/mail.md), after AI translation, for `settings.manage`.
    #
    # - Server, Port, Security (STARTTLS / TLS, a segmented control), Sender
    #   name and Sender address are fields of the one Settings form, saved
    #   with its save bar. Choosing a security puts its port (587 / 465) into
    #   Port unless a port was typed (`admin--settings--mail`).
    # - The login is `MailLoginComponent`: instant forms, written once.
    # - The state (`MailStateComponent`) sits under the title.
    # - "Send test mail" is the foot (`MailTestResultComponent`).
    #
    # A field the host's environment sets (`MailSettings#from_host?`) is no
    # field of the form: a sunken box with its value and "Set by the host",
    # nothing posted, so a Save never sends it (and `Settings::Save` refuses
    # one forged in). With every field from the host the card says so once,
    # and only the test button is left to press.
    #
    # `mail_settings` is the `MailSettings` of the stored row (what the state
    # and the host's fields are read from); `values` what the fields show
    # (typed beats stored after a refused save); `errors` the refused save's
    # `ActiveModel::Errors`, or nil.
    class MailCardComponent < Admin::AdminComponent
      FIELDS = %i[mail_server mail_port mail_security mail_sender_name mail_sender_address].freeze
      SETTING = {
        mail_server: :server, mail_port: :port, mail_security: :security,
        mail_sender_name: :sender_name, mail_sender_address: :sender_address
      }.freeze
      SECURITIES = %w[starttls tls].freeze
      # The port each security is normally served on (spec, M1).
      PORTS = { "starttls" => 587, "tls" => 465 }.freeze

      def initialize(site_setting:, mail_settings:, values:, errors: nil)
        @site_setting = site_setting
        @mail_settings = mail_settings
        @values = values
        @errors = errors
      end

      def from_host?(name) = mail_settings.from_host?(SETTING.fetch(name))

      def all_from_host? = mail_settings.all_from_host?

      # What the host set, as text (the value is no secret: server, port,
      # security, sender).
      def host_value(name)
        value = mail_settings.value(SETTING.fetch(name)).to_s
        name == :mail_security && value.present? ? t(".#{value}", default: value) : value
      end

      def value(name) = values.mail(name).to_s

      # The security shown checked: what was typed or stored, else STARTTLS
      # (`MailSettings::DEFAULT_SECURITY`): a site that never chose one is
      # sent with STARTTLS, so that is what the control says.
      def security = SECURITIES.include?(value(:mail_security)) ? value(:mail_security) : MailSettings::DEFAULT_SECURITY

      def input_id(name) = "settings-#{name}"

      def field_errors(name) = errors.respond_to?(:full_messages_for) ? errors.full_messages_for(name) : []

      def segment_class = Admin::Fields::SelectField::SEGMENT_CLASS

      # Where "Send test mail" sends: the person looking at the card.
      def address = Current.user&.email_address.to_s

      private

      attr_reader :site_setting, :mail_settings, :values, :errors
    end
  end
end
