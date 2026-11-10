module Admin
  module SettingsScreen
    # The alert a mail failure is shown in, warn and not danger, since nothing
    # typed is lost: the sentence first, then the server's one reply line in
    # mono, already scrubbed of the login (`MailFailure`). It is the compact
    # warn notice (`Admin::Ui::NoticeComponent`), as the insecure notice is.
    # Both are text: the line is whatever the server answered.
    class MailAlertComponent < Admin::AdminComponent
      def initialize(sentence:, line: nil, **html)
        @sentence = sentence
        @line = line
        @html = html
      end

      def call
        render(Admin::Ui::NoticeComponent.new(tone: :warn, size: :compact, class: @html[:class])) do
          safe_join([ tag.p(@sentence), (tag.p(tag.code(@line, class: "font-cs-mono break-words"), class: "mt-1") if @line.present?) ].compact)
        end
      end
    end
  end
end
