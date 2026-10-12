module Admin
  module EditorScreen
    # The two parts of the editor header that follow what is published
    # (drafts spec §4.4, §6): `:chip` (`#publishing-chip`, beside the status
    # chip) and `:actions` (`#publishing-actions`, in the row of buttons).
    #
    # ONLY THE CHIP IS EVER REPLACED. A save's answer (`Admin::PublishingState`)
    # and another tab's change (`admin--editing--live`, `Admin::EditingController#publishing`)
    # redraw `#publishing-chip`; the "Publish changes" FORM in `#publishing-actions`
    # is drawn once, with the page, and stays: the write queue holds a form
    # that was pressed while a save was out (`admin--saving--queue-hold`), and
    # a form replaced by the very answer it waits for is gone when the queue
    # is drained, so the press would be dropped (docs/reference/save-rule-and-write-queue.md).
    # Whether the form SHOWS is a mark inside the chip: `[data-publish-changes-offered]`
    # (the header has the `group/publishing` class; the form is `display: none`
    # unless the header `has` the mark, so a test reads the mark, not the button).
    #
    # WHAT TO SHOW is `Publishing::State`'s (handed in as `state:` by the
    # header, which read it once): the chip when the record `changes?`, the
    # button when its `actions` hold `:publish_changes` and the viewer may
    # publish. The "No address" chip (`Publishing::Addressless`) is a second
    # fact, drawn in the same part because it stands in the same place.
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

      def publish_changes? = state.action?(:publish_changes) && may_publish?

      def publish_url = helpers.admin_publishing_publish_path(kind: type, id: record.id, **url_options)

      private

      attr_reader :record, :part, :url_options
    end
  end
end
