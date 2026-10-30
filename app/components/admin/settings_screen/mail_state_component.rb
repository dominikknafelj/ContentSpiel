module Admin
  module SettingsScreen
    # The Mail card's state (spec "The states", design answer M3): a dot and
    # a word, never colour alone, and under them the state's sentence. While
    # the last send failed, the stored failure follows: its sentence and the
    # server's line in mono (the card is `settings.manage`'s, who may read the
    # line; System status shows the sentence alone).
    #
    #   Not set up         hollow circle in --cs-meta
    #   Saved, not tested  filled warn dot
    #   Working            filled ok dot
    #   Last send failed   danger dot: a real mail was lost
    #
    # Its own element (`ID`), because "Send test mail" changes the state and
    # its answer replaces this part of the card alone. Every word is
    # `admin.mail.states.*` (config/locales/admin/mail.en.yml), shared with
    # the System status row.
    class MailStateComponent < Admin::AdminComponent
      ID = "settings-mail-state".freeze

      DOTS = {
        not_set_up: "border border-meta", untested: "bg-warn", working: "bg-ok", failed: "bg-danger"
      }.freeze

      def initialize(mail_settings:)
        @mail_settings = mail_settings
      end

      def call
        tag.div(id: ID, class: "mt-2", data: { mail_state: state }) do
          safe_join([
            tag.p(class: "flex items-center gap-1.5 text-sm text-ink") do
              safe_join([ tag.span(class: "size-2 shrink-0 rounded-full #{DOTS.fetch(state)}", aria: { hidden: true }),
                tag.span(t("admin.mail.states.#{state}.word"), class: "font-semibold") ])
            end,
            tag.p(sentence, class: "mt-1 text-sm text-dim"),
            failure_alert
          ].compact)
        end
      end

      def state = mail_settings.state

      def sentence = ::MailStateSentence.for(mail_settings)

      private

      attr_reader :mail_settings

      def failure = (@failure ||= ::MailFailure.load(mail_settings.failure) || ::MailFailure.new(key: "other", line: ""))

      def failure_alert
        return unless state == :failed

        render(MailAlertComponent.new(sentence: failure.sentence(server: mail_settings.value(:server), port: mail_settings.value(:port)), line: failure.line, class: "mt-2"))
      end
    end
  end
end
