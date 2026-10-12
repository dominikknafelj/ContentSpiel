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

      # One block's address with `:block_id` for the script to fill in, for a
      # page (a post has no blocks of its own to fetch). The route takes
      # digits only, so it is built for 0 and the 0 put back as the name.
      def block_url
        return unless @record.is_a?(::Page)

        helpers.admin_editing_block_path(kind: kind, id: @record.id, **@url_options, block_id: 0).sub("/blocks/0", "/blocks/:block_id")
      end

      def region_data
        route = { kind: kind, id: @record.id, **@url_options }
        {
          controller: "admin--editing--live admin--editing--hold", live_part: "waiting",
          "admin--editing--live-kind-value": kind, "admin--editing--live-id-value": @record.id,
          "admin--editing--live-blocks-url-value": (helpers.admin_editing_blocks_path(**route) if @record.is_a?(::Page)),
          "admin--editing--live-block-url-value": block_url,
          "admin--editing--live-record-url-value": helpers.admin_editing_record_path(**route),
          "admin--editing--live-notice-value": ::Editing::NOTICE.in_milliseconds,
          "admin--editing--hold-claim-url-value": helpers.admin_editing_claim_path(**route),
          "admin--editing--hold-release-url-value": helpers.admin_editing_release_path(**route),
          "admin--editing--hold-take-over-url-value": helpers.admin_editing_take_over_path(**route),
          "admin--editing--hold-hand-over-url-value": helpers.admin_editing_hand_over_path(**route),
          "admin--editing--hold-withdraw-url-value": helpers.admin_editing_withdraw_path(**route),
          "admin--editing--hold-block-url-value": block_url,
          "admin--editing--hold-hold-value": ::Editing::HOLD.in_milliseconds,
          "admin--editing--hold-pass-over-value": ::Editing::PASS_OVER.in_milliseconds,
          "admin--editing--hold-notice-value": ::Editing::NOTICE.in_milliseconds,
          "admin--editing--hold-rules-value": ::Admin::EditorScreen::HeldFields.rules.to_json
        }.compact
      end
    end
  end
end
