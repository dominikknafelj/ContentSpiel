module Admin
  module PostsScreen
    # The posts list's bulk bar (design pass round 2, Task 17, handoff §4.3):
    # accent-tint, hidden until rows are ticked, then "3 selected · Publish ·
    # Move to trash · Clear". The count is announced by an always-present
    # `role="status"` (`aria-live="polite"`) beside it, which `admin--posts--bulk-select`
    # writes ("2 posts selected"); the bar itself toggles `hidden`. It holds no checkboxes of its own: `admin--posts--bulk-select`
    # (on the list's wrapper) tracks the ticked rows and fills each `ids`
    # container -- one in the Publish form, one in the trash confirmation's
    # form -- with a hidden `ids[]` per row. Both forms sit here, outside the
    # table (forms can't nest) and carry the list's own filters
    # (`list_params`) as hidden fields, so `POST /posts/bulk` can send the
    # editor back to the page they were on.
    #
    # Only the actions the viewer holds anywhere are offered (`can?` without a
    # record): which of the ticked posts they may act on is `Posts::Bulk`'s
    # judgement, one post at a time, reported back as "refused".
    #
    # Moving to the trash is destructive, so it asks first
    # (`Admin::Ui::ConfirmDialogComponent`, destructive), naming how many; the
    # confirm form lives in the dialog, a sibling of the Publish form, never
    # inside it.
    class BulkBarComponent < Admin::AdminComponent
      TRASH_DIALOG_ID = "bulk-trash-dialog".freeze

      # `list_fields` are the list's own query params as a Hash of plain
      # strings (what `list_params` returns), repeated as hidden fields.
      def initialize(list_fields: {})
        @list_fields = list_fields
      end

      def render? = may_publish? || may_trash?

      def may_publish? = can?("posts.publish")

      def may_trash? = can?("posts.delete")

      def trash_dialog_id = TRASH_DIALOG_ID

      private

      attr_reader :list_fields
    end
  end
end
