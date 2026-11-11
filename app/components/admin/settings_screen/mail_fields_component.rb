module Admin
  module SettingsScreen
    # The Mail form's fields, one drawing for Settings → Mail
    # (`MailCardComponent`, inside `#settings-form`) and the setup wizard's
    # Mail step (`app/views/setup/mail.html.erb`), in two groups:
    #
    # - Server (the `media` chip): Server, Port, Security, then the `login`
    #   slot, which each screen fills with its own login (the card's instant
    #   `MailLoginComponent`, the wizard's two plain inputs);
    # - Sender (the `text` chip): Sender name, Sender address.
    #
    # Each group is `role="group"`, named by its meta line; the chip is
    # decoration. Each field's wrapper carries `data-field-name` (its column),
    # which the save bar names it by.
    #
    # Security is the segmented control, inside a fieldset with its legend.
    # Its radios carry their port (`PORTS`) and `mail-port`'s action, and
    # Port is `mail-port`'s target: choosing a security puts its port into
    # Port unless another port was typed. The caller's root carries the
    # `mail-port` controller.
    #
    # A field the host sets is `HostValueComponent` and no input, so it is
    # never posted (and `Settings::Save` refuses one forged in).
    #
    # - `value` is a callable `(column) -> String`: what the field shows (on
    #   Settings typed beats stored, `Values#mail`; in the wizard also the
    #   step's defaults).
    # - `changed` is a callable `(column) -> "saved" | nil`: the wrapper's
    #   `data-save-bar-changed` after a refused save (`Values#saved_change`);
    #   nil where there is no save bar.
    # - `errors` is the refused save's `ActiveModel::Errors`, or nil: each
    #   field's sentence stands under it.
    class MailFieldsComponent < Admin::AdminComponent
      FIELDS = %i[mail_server mail_port mail_security mail_sender_name mail_sender_address].freeze
      # Each column's `MailSettings` field: what `from_host?` is asked of.
      SETTING = {
        mail_server: :server, mail_port: :port, mail_security: :security,
        mail_sender_name: :sender_name, mail_sender_address: :sender_address
      }.freeze
      SECURITIES = %w[starttls tls].freeze
      # The port each security is normally served on.
      PORTS = { "starttls" => 587, "tls" => 465 }.freeze
      GROUP_CLASS = "flex flex-col gap-3.5 rounded-tile bg-paper p-3".freeze

      renders_one :login

      def initialize(mail_settings:, value:, name_prefix:, id_prefix:, errors: nil, changed: nil)
        @mail_settings = mail_settings
        @value = value
        @name_prefix = name_prefix
        @id_prefix = id_prefix
        @errors = errors
        @changed = changed
      end

      def from_host?(name) = mail_settings.from_host?(SETTING.fetch(name))

      def shown(name) = value.call(name).to_s

      # The security shown checked: what was typed or stored, else STARTTLS
      # (`MailSettings::DEFAULT_SECURITY`): a site that never chose one is
      # sent with STARTTLS, so that is what the control says.
      def security = SECURITIES.include?(shown(:mail_security)) ? shown(:mail_security) : MailSettings::DEFAULT_SECURITY

      def input_name(name) = "#{name_prefix}[#{name}]"

      def input_id(name) = "#{id_prefix}#{name}"

      def group_id(group) = "#{id_prefix}mail-#{group}-group"

      def label(name) = t(".#{SETTING.fetch(name)}")

      def wrapper_data(name) = { field_name: name, save_bar_changed: changed&.call(name) }

      def host_value(name) = Admin::SettingsScreen::HostValueComponent.new(field: SETTING.fetch(name), label: label(name), mail_settings: mail_settings)

      def field_errors(name) = errors.respond_to?(:full_messages_for) ? errors.full_messages_for(name) : []

      # The securities as the shared segmented control's radios, each telling
      # `mail-port` the port it goes with.
      def security_segments
        SECURITIES.map do |option|
          { label: t(".#{option}"), value: option, id: "#{input_id(:mail_security)}-#{option}", current: security == option,
            data: { action: "change->mail-port#security", port: PORTS.fetch(option) } }
        end
      end

      private

      attr_reader :mail_settings, :value, :name_prefix, :id_prefix, :errors, :changed
    end
  end
end
