module Admin
  # See `Admin::MediaLibrary::GridComponent`'s own class comment for why
  # this namespace is `MediaLibrary`, not `Media`.
  module MediaLibrary
    # The bar of the Media screen's selection mode (`select=1`, the card
    # StudioMediaFolders, D6), at elevation 3 on the popover ground, sticky
    # under the top offset over the grid it acts on: "3 selected", "Select
    # all 34" (the tiles this page draws, `count_on_page`; "All 34 selected"
    # once they all are), "Clear", a spacer that keeps the room for "Move to
    # trash…" and "Download" (spec §5.3), "Move to…" (the Move to… dialog for
    # the selection) and "Done" (the place again, without `select`:
    # `done_url`).
    #
    # The selection is `admin--media--selection`'s, which writes the count,
    # the Select all words, Move to…'s ids and title (the params
    # `MoveDialogComponent.images_trigger` draws here with no ids) and the
    # status. The count is announced by an always-present `role="status"`
    # before the bar, as the posts list's bulk bar does: a live region
    # announces changes, and the bar's own words change with every press.
    #
    # Its words are `admin.components.media_library.selection.*`, the
    # script's in `data-messages` on the bar.
    class SelectionBarComponent < AdminComponent
      MESSAGES = %w[count select_all all_selected].map { |key| "components.media_library.selection.#{key}" }.freeze

      def initialize(count_on_page:, done_url:)
        @count_on_page = count_on_page
        @done_url = done_url
      end

      def count_on_page = @count_on_page.to_i

      attr_reader :done_url

      # The words are `selection.*` (the card's), not the class's own scope.
      def words(key, **vars) = t("admin.components.media_library.selection.#{key}", **vars)

      def bar_messages = messages_data(*MESSAGES)

      def target(name) = { "admin--media--selection-target": name }

      def move_data = MoveDialogComponent.images_trigger([], title: "").merge(target("move"))

      def move_classes = "#{Admin::Ui::ButtonComponent.classes(:secondary, size: :small)} gap-1.5"

      def done_data = { turbo_frame: "content", turbo_action: "advance" }.merge(target("done"))
    end
  end
end
