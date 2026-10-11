module Admin
  module EditorScreen
    # The element an editor's live scripts stand on (live-editing spec §6):
    # around the page's settings and blocks, or a post's form. It is a part of
    # the page that holds a cable subscription of its own, so the server
    # renders `data-live-part="waiting"` and the script writes "answered"
    # (`live/state`; `await_notes_live` in the system tests waits for it).
    # Everything the scripts need from the server is a value here: they hold
    # no address, no number and no wording.
    class LiveRegionComponent < AdminComponent
      def initialize(record:, locale:, url_options: {})
        @record = record
        @locale = locale
        @url_options = url_options
      end

      def kind = ::RecordKinds.of(@record).name

      def region_data
        route = { kind: kind, id: @record.id, **@url_options }
        {
          controller: "admin--editing--live", live_part: "waiting",
          "admin--editing--live-kind-value": kind, "admin--editing--live-id-value": @record.id,
          "admin--editing--live-blocks-url-value": (helpers.admin_editing_blocks_path(**route) if @record.is_a?(::Page)),
          "admin--editing--live-block-url-value": (helpers.admin_editing_block_path(**route, block_id: 0).sub("/blocks/0", "/blocks/:block_id") if @record.is_a?(::Page)),
          "admin--editing--live-record-url-value": helpers.admin_editing_record_path(**route),
          "admin--editing--live-notice-value": ::Editing::NOTICE.in_milliseconds
        }.compact
      end
    end
  end
end
