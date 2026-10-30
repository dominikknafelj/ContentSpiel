module Admin
  module Ui
    # "Last send failed 14 Oct, 09:12: the server refused the login." with
    # "Open Mail settings →": the dashboard's alert while mail's last send
    # failed (spec "The states", design answer M3; plan ruling P3). It is for
    # whoever holds `settings.manage`, who can fix it: the dashboard decides
    # that and hands a `mail_settings` only to them. It draws itself only in
    # the one state, `failed`, and stays until a send succeeds, because a real
    # mail was lost; resets and invites stay on meanwhile (`MailSettings#ready?`).
    #
    # The sentence is `MailStateSentence`'s, the card's and System status's
    # own, so it names a reason and never the server's line.
    #
    # In the insecure notice's style (`InsecureNoticeComponent`): a warn alert,
    # `role=alert`, never danger on a screen of cards.
    class MailFailedNoticeComponent < AdminComponent
      BASE_CLASS = "rounded-cs border border-warn bg-warn-tint px-3 py-2.5 text-[13px] leading-normal text-warn-ink".freeze

      # `href` is where "Open Mail settings →" goes, resolved by the screen.
      # `class:` places the notice and is added to the component's own.
      def initialize(mail_settings:, href:, **html)
        @mail_settings = mail_settings
        @href = href
        @html = html
      end

      def render? = @mail_settings.state == :failed

      private

      def sentence = ::MailStateSentence.for(@mail_settings)

      def attributes = @html.merge(id: "mail-failed-notice", role: "alert", class: [ BASE_CLASS, @html[:class] ].compact.join(" "))
    end
  end
end
