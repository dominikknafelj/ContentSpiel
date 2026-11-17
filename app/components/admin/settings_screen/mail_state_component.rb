module Admin
  module SettingsScreen
    # The Mail card's state, in two parts of the card's head, each its own
    # element because "Send test mail" and a login's write change the state
    # and their answers replace these two alone:
    #
    # - `part: :chip` (`ID`), at the head's end: the state chip alone (a dot
    #   and a word, never colour alone), so the head says the state once.
    # - `part: :note` (`NOTE_ID`), the head's note under the intro: what the
    #   state means for the site, in `text-small` dim words ("Password resets
    #   and invites are off until mail is set up.", "Mail is saved but not
    #   tested yet.", "The last mail could not be sent."), and nothing while
    #   mail works. A site that is not set up for a reason the person must
    #   fix (no `PUBLIC_HOST`, a sender that is not one address) keeps that
    #   reason's sentence (`MailStateSentence`), the words System status says
    #   too. While the last send failed, the stored failure follows: its
    #   sentence and the server's line in mono (the card is
    #   `settings.manage`'s, who may read the line; System status shows the
    #   sentence alone).
    #
    # `TONES` is the one map from a mail state to its chip's tone, public so
    # that every component drawing a mail state reads it: not set up is off,
    # saved but not tested is warn, working is ok, and a failed send is
    # danger, because a real mail was lost. The chip's words are
    # `admin.mail.states.*.word` (config/locales/admin/mail.en.yml), shared
    # with the System status row.
    class MailStateComponent < Admin::AdminComponent
      ID = "settings-mail-state".freeze
      NOTE_ID = "settings-mail-state-note".freeze

      TONES = { not_set_up: :off, untested: :warn, working: :ok, failed: :danger }.freeze

      def initialize(mail_settings:, part: :chip)
        raise ArgumentError, "unknown part #{part.inspect}" unless %i[chip note].include?(part)

        @mail_settings = mail_settings
        @part = part
      end

      def call
        @part == :chip ? chip : note
      end

      def state = mail_settings.state

      private

      attr_reader :mail_settings

      def chip
        tag.div(id: ID, data: { mail_state: state }) do
          render(Admin::Ui::StateChipComponent.new(tone: TONES.fetch(state), label: t("admin.mail.states.#{state}.word")))
        end
      end

      def note
        tag.div(id: NOTE_ID, data: { mail_state: state }) do
          safe_join([
            (tag.p(sentence, class: "mt-1 text-small text-dim", data: { mail_state_note: true }) if sentence),
            failure_alert
          ].compact)
        end
      end

      # The note's words: the state's consequence, or the reason a site is
      # not set up when it is one the person must fix.
      def sentence
        return ::MailStateSentence.for(mail_settings) if state == :not_set_up && mail_settings.not_set_up_key != "sentence"

        { not_set_up: t(".notes.not_set_up"), untested: t(".notes.untested"), failed: t(".notes.failed") }[state]
      end

      def failure = (@failure ||= ::MailFailure.load(mail_settings.failure) || ::MailFailure.new(key: "other", line: ""))

      def failure_alert
        return unless state == :failed

        render(Admin::Ui::MailAlertComponent.new(sentence: failure.sentence(server: mail_settings.value(:server), port: mail_settings.value(:port)), line: failure.line, class: "mt-2"))
      end
    end
  end
end
