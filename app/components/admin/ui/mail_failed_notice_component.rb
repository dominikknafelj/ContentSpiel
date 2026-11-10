module Admin
  module Ui
    # "Last send failed 14 Oct, 09:12: the server refused the login." with
    # "Open Mail settings →": the dashboard's alert while mail's last send
    # failed. It is for
    # whoever holds `settings.manage`, who can fix it: the dashboard decides
    # that and hands a `mail_settings` only to them. It draws itself only in
    # the one state, `failed`, and stays until a send succeeds, because a real
    # mail was lost; resets and invites stay on meanwhile (`MailSettings#ready?`).
    #
    # The sentence is `MailStateSentence`'s, the card's and System status's
    # own, so it names a reason and never the server's line.
    #
    # The compact warn notice (`Admin::Ui::NoticeComponent`), as the insecure
    # notice is: an alert, never danger on a screen of cards.
    class MailFailedNoticeComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "An alert (role=alert) of one sentence with a link to Mail settings.",
        motion: :none,
        content_edges: %i[long],
        widths: :from_container,
        interface: %i[mail_settings href],
        limits: [
          "It draws itself only while mail's last send failed, and who sees it is the screen's.",
          "The sentence is MailStateSentence's: it names a reason and never the server's line."
        ],
        states: %i[rest hover focus],
        keys: %w[open_settings],
        slots: [],
        controller: nil
      )

      # `href` is where "Open Mail settings →" goes, resolved by the screen.
      # `class:` places the notice and is added to the notice's own.
      def initialize(mail_settings:, href:, **html)
        @mail_settings = mail_settings
        @href = href
        @html = html
      end

      def render? = @mail_settings.state == :failed

      private

      def sentence = ::MailStateSentence.for(@mail_settings)
    end
  end
end
