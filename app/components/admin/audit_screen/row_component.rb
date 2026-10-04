module Admin
  module AuditScreen
    # One event in the audit log (design pass round 3, Task 15): the time
    # ("16:05", or "16:05–16:31" for a coalesced span), an avatar, the sentence
    # (`Audit::Sentence`, drawn by `SentenceComponent`), the channel chip and the
    # raw action key in mono at the right -- in warn ink for the security keys.
    # The whole row opens the event page: the time is the link, stretched over
    # the row, and the subject's own link sits above it (a link can't nest in a
    # link). Everything comes from the sentence and the event, so a row never
    # queries.
    class RowComponent < Admin::AdminComponent
      def initialize(event:, sentence:, event_path:)
        @event = event
        @sentence = sentence
        @event_path = event_path
      end

      attr_reader :event, :sentence, :event_path

      def dom_id = ActionView::RecordIdentifier.dom_id(event)

      def time_text = TimeSpan.short(event)

      def key_class = sentence.security ? "text-warn-ink" : "text-meta"

      # The avatar's letter: a person's initial; "S" for the system, "–" for an
      # event nobody made (a failed sign-in).
      def initial
        actor = sentence.actor
        return "–" if actor.none

        Admin::UserNameComponent.new(user: actor.user, user_id: actor.user_id).label.to_s.strip[0].to_s.upcase
      end
    end
  end
end
