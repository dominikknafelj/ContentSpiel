module Admin
  module SettingsScreen
    # A mail field the host's environment sets (`MailSettings#from_host?`),
    # on Settings → Mail and in the wizard's Mail step: its label, a sunken
    # box and "Set by the host", with no input, so nothing of it is posted.
    #
    # `field` is a `MailSettings` field (`:server`, `:username`), never a
    # column. A half of the login (`MailLoginComponent.secret?`) is a
    # credential: its box is `MailLoginComponent::MASK`, hidden from a screen
    # reader, and its value is never asked of `mail_settings`, so it cannot
    # reach the page, Turbo's snapshot or the browser's cache
    # (`test/integration/setup_mail_step_test.rb`). Any other field shows the
    # host's value, the security in its words.
    class HostValueComponent < Admin::AdminComponent
      BOX = "mt-1 rounded-cs border border-line bg-sunken px-3 py-2 text-sm".freeze

      def initialize(field:, label:, mail_settings:)
        @field = field.to_sym
        @label = label
        @mail_settings = mail_settings
      end

      def call
        tag.div(data: { host_field: field }) do
          safe_join([ tag.span(label, class: setup_label_class), box, tag.p(t(".set_by_host"), class: "mt-1 text-sm text-meta") ])
        end
      end

      private

      attr_reader :field, :label, :mail_settings

      def box
        return tag.div(MailLoginComponent::MASK, class: "#{BOX} text-dim", aria: { hidden: true }) if MailLoginComponent.secret?(field)

        tag.div(shown_value, class: "#{BOX} text-ink")
      end

      def shown_value
        value = mail_settings.value(field).to_s
        field == :security && value.present? ? t(".#{value}", default: value) : value
      end
    end
  end
end
