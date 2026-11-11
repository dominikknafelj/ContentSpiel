module Admin
  module AuditScreen
    # One event in the audit log: the time
    # ("16:05", or "16:05–16:31" for a coalesced span), the actor's small mark
    # (`Admin::Ui::ActorAvatarComponent` at `:sm`, the dashboard's too), the
    # sentence (`Audit::Sentence`, drawn by `Admin::Ui::AuditSentenceComponent`), the channel
    # chip and the raw action key in mono meta at the right. A security event
    # says so in words: a warn "Security" state chip before its key, whose
    # colour is the same as any other key's, so the colour is never the only
    # cue. The whole row opens the event page: the time is the link,
    # stretched over the row, and the subject's own link sits above it (a
    # link can't nest in a link). Everything comes from the sentence and the
    # event, so a row never queries.
    class RowComponent < Admin::AdminComponent
      ROW_CLASS = "relative flex flex-wrap items-center gap-x-3 gap-y-1 border-b border-line px-4 py-2.5 last:border-b-0 hover:bg-paper".freeze

      def initialize(event:, sentence:, event_path:)
        @event = event
        @sentence = sentence
        @event_path = event_path
      end

      attr_reader :event, :sentence, :event_path

      def dom_id = ActionView::RecordIdentifier.dom_id(event)

      def time_text = TimeSpan.short(event)
    end
  end
end
