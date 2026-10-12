module Admin
  module EditorScreen
    # The two parts of the editor header that follow what is published
    # (drafts spec §4.4, §6): `:chip` (`#publishing-chip`, beside the status
    # chip) and `:actions` (`#publishing-actions`, in the row of buttons).
    #
    # ONLY THE CHIP IS EVER REPLACED. A save's answer (`Admin::PublishingState`)
    # and another tab's change (`admin--editing--live`, `Admin::EditingController#publishing`)
    # redraw `#publishing-chip`; what is in `#publishing-actions` is drawn
    # once, with the page, and stays. The actions are two
    # buttons that OPEN A DIALOG ("Discard changes…", "Publish changes…"),
    # and the forms a press sends are in those dialogs
    # (`PublishChangesDialogComponent`), drawn once as well: the write queue
    # holds a form that was pressed while a save was out
    # (`admin--saving--queue-hold`), and a form replaced by the very answer it
    # waits for is gone when the queue is drained, so the press would be
    # dropped (docs/reference/save-rule-and-write-queue.md).
    # Whether a button SHOWS is a mark inside the chip:
    # `[data-publish-changes-offered]`, `[data-discard-changes-offered]` (the
    # header has the `group/publishing` class; a button's wrapper is
    # `display: none` unless the header `has` its mark, so a test reads the
    # mark, not the button).
    #
    # WHAT TO SHOW is `Publishing::State`'s (handed in as `state:` by the
    # header, which read it once): the chip when the record `changes?`, each
    # button when its action is among the state's `actions` and the viewer
    # has the right (publish: the right to publish; discard: what editing the
    # record needs), and the time a scheduled change waits for. The "No
    # address" chip (`Publishing::Addressless`) is a second fact, drawn in
    # the same part because it stands in the same place.
    class PublishingStateComponent < Admin::AdminComponent
      PARTS = { chip: "publishing-chip", actions: "publishing-actions" }.freeze

      def initialize(record:, part:, url_options: {}, state: nil)
        raise ArgumentError, "unknown part #{part.inspect}" unless PARTS.key?(part)

        @record = record
        @part = part
        @url_options = url_options
        @state = state
      end

      def id = PARTS.fetch(part)

      def chip? = part == :chip

      def type = record.is_a?(::Page) ? "page" : "post"

      def state = @state ||= ::Publishing::State.of(record)

      def changes? = state.changes?

      def no_address? = ::Publishing::Addressless.record?(record)

      def may_publish? = can?("#{type}s.publish", record)

      # What editing a published or scheduled record needs (`AccessControl::OwnerRule`).
      def may_discard? = can_edit?(record)

      def publish_changes? = state.action?(:publish_changes) && may_publish?

      def discard_changes? = state.action?(:discard_changes) && may_discard?

      def dialog_id = PublishChangesDialogComponent.dialog_id_for(record)

      def discard_dialog_id = PublishChangesDialogComponent.discard_dialog_id_for(record)

      # When the change that waits for its time comes into force, worded, or nil.
      def scheduled_time
        at = state.pending_at or return
        I18n.l(at.in_time_zone(Current.site.effective_time_zone), format: :"admin.datetime")
      end

      private

      attr_reader :record, :part, :url_options
    end
  end
end
