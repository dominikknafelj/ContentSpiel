module Admin
  module Ui
    # The alert a mail failure is shown in, warn and not danger, since nothing
    # typed is lost: the sentence first, then the server's one reply line in
    # mono, already scrubbed of the login (`MailFailure`). It is the compact
    # warn notice (`Admin::Ui::NoticeComponent`), as the insecure notice is.
    # Both are text: the line is whatever the server answered.
    # `class:` places the alert and is added to the notice's own.
    class MailAlertComponent < Admin::AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "A warn alert (role=alert, from the notice) of the failure's sentence, then the server's one reply line in mono; the line is text, never markup.",
        motion: :none,
        content_edges: %i[none long],
        widths: :from_container,
        interface: %i[sentence line],
        limits: [
          "It is only a drawing of a failure that already happened: the sentence is MailFailure's and the line is the server's, scrubbed of the login before it gets here.",
          "It is warn and never danger: nothing typed is lost."
        ],
        states: %i[rest with_line],
        keys: [],
        slots: [],
        controller: nil,
        keyboard: "It takes no focus: a notice of words, with no link or control of its own, beside the Send test mail button and the state chip, which the keyboard stops on instead."
      )

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
