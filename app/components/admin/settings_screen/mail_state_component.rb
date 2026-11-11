module Admin
  module SettingsScreen
    # The Mail card's state: a state chip (a dot and a word, never colour
    # alone) and under it the state's sentence. While the last send failed,
    # the stored failure follows: its sentence and the server's line in mono
    # (the card is `settings.manage`'s, who may read the line; System status
    # shows the sentence alone).
    #
    # `TONES` is the one map from a mail state to its chip's tone, public so
    # that every component drawing a mail state reads it: not set up is off,
    # saved but not tested is warn, working is ok, and a failed send is
    # danger, because a real mail was lost.
    #
    # Its own element (`ID`), because "Send test mail" changes the state and
    # its answer replaces this part of the card alone. Every word is
    # `admin.mail.states.*` (config/locales/admin/mail.en.yml), shared with
    # the System status row.
    class MailStateComponent < Admin::AdminComponent
      ID = "settings-mail-state".freeze

      TONES = { not_set_up: :off, untested: :warn, working: :ok, failed: :danger }.freeze

      def initialize(mail_settings:)
        @mail_settings = mail_settings
      end

      def call
        tag.div(id: ID, class: "mt-2", data: { mail_state: state }) do
          safe_join([
            tag.p(render(Admin::Ui::StateChipComponent.new(tone: TONES.fetch(state), label: t("admin.mail.states.#{state}.word")))),
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

        render(Admin::Ui::MailAlertComponent.new(sentence: failure.sentence(server: mail_settings.value(:server), port: mail_settings.value(:port)), line: failure.line, class: "mt-2"))
      end
    end
  end
end
