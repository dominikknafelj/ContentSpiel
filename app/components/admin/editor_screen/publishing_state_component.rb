module Admin
  module EditorScreen
    # The two parts of the editor header that follow what is published
    # (drafts spec §4.4, §6): `:chip` (`#publishing-chip`, beside the status
    # chip) and `:actions` (`#publishing-actions`, in the row of buttons).
    # Each is always rendered, empty when there is nothing to say, so that a
    # save's answer can replace it (`Admin::PublishingState`).
    #
    # WHAT TO SHOW is `Publishing::State`'s, asked here and nowhere else in the
    # header: the chip when the record `changes?`, the button when its
    # `actions` hold `:publish_changes` and the viewer may publish. The
    # "No address" chip (`Publishing::Addressless`) is a second fact, drawn
    # in the same part because it stands in the same place.
    class PublishingStateComponent < Admin::AdminComponent
      PARTS = { chip: "publishing-chip", actions: "publishing-actions" }.freeze

      def initialize(record:, part:, url_options: {})
        raise ArgumentError, "unknown part #{part.inspect}" unless PARTS.key?(part)

        @record = record
        @part = part
        @url_options = url_options
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
