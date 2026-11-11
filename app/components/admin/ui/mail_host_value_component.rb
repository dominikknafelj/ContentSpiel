module Admin
  module Ui
    # A mail field the host's environment sets (`MailSettings#from_host?`),
    # on Settings → Mail and in the wizard's Mail step: its label, a sunken
    # box and "Set by the host", with no input, so nothing of it is posted.
    #
    # `field` is a `MailSettings` field (`:server`, `:username`), never a
    # column. A half of the login (`MailHostValueComponent.secret?`) is a
    # credential: its box is `MASK`, hidden from a screen
    # reader, and its value is never asked of `mail_settings`, so it cannot
    # reach the page, Turbo's snapshot or the browser's cache
    # (`test/integration/setup_mail_step_test.rb`). Any other field shows the
    # host's value, the security in its words.
    class MailHostValueComponent < Admin::AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A label, a sunken box with the host's value (or the mask, hidden from a screen reader) and the sentence \"Set by the host\": plain words with no input, so nothing of it is posted and nothing can be edited.",
        motion: :none,
        content_edges: %i[none long],
        widths: :from_container,
        interface: %i[field label mail_settings],
        limits: [
          "`field` is a MailSettings field, never a column; a half of the login is a credential, so its value is never asked of `mail_settings` and only the mask reaches the page.",
          "It is only a drawing of a field the host sets: Settings::Save refuses a save that names one."
        ],
        states: %i[rest masked],
        keys: %w[set_by_host starttls tls none],
        slots: [],
        controller: nil,
        keyboard: "It takes no focus: a label, a box of words and a sentence, with no input or link; the fields around it are the Mail form's, which the keyboard stops on."
      )

      # What a half of the login the host sets is drawn as: never its value.
      MASK = "••••••••".freeze
      BOX = "mt-1 rounded-cs border border-line bg-sunken px-3 py-2 text-sm".freeze

      # Whether a mail field is a half of the login, whose value no screen shows.
      def self.secret?(field) = MailSettings::LOGIN_FIELDS.include?(field.to_sym)

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
        return tag.div(MASK, class: "#{BOX} text-dim", aria: { hidden: true }) if MailHostValueComponent.secret?(field)

        tag.div(shown_value, class: "#{BOX} text-ink")
      end

      def shown_value
        value = mail_settings.value(field).to_s
        field == :security && value.present? ? t(".#{value}", default: value) : value
      end
    end
  end
end
