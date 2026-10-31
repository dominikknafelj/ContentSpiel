module Admin
  module SettingsScreen
    # The warn alert a mail failure is shown in (design answer M1: warn, not
    # danger -- nothing typed is lost): the sentence first, then the server's
    # one reply line in mono, already scrubbed of the login (`MailFailure`).
    # The insecure notice's look (`Admin::Ui::InsecureNoticeComponent`). Both
    # are text: the line is whatever the server answered.
    class MailAlertComponent < Admin::AdminComponent
      BASE_CLASS = "rounded-cs border border-warn bg-warn-tint px-3 py-2.5 text-[13px] leading-normal text-warn-ink".freeze

      def initialize(sentence:, line: nil, **html)
        @sentence = sentence
        @line = line
        @html = html
      end

      def call
        tag.div(role: "alert", class: [ BASE_CLASS, @html[:class] ].compact.join(" ")) do
          safe_join([ tag.p(@sentence), (tag.p(tag.code(@line, class: "font-cs-mono break-words"), class: "mt-1") if @line.present?) ].compact)
        end
      end
    end
  end
end
