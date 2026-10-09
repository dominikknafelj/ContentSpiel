module Admin
  module EditorScreen
    # "Delete this block?" -- the confirmation behind every "Delete block…" of
    # the page editor, one per block, found by its id (`dialog_id`, what the
    # trigger names: `dialog_trigger`).
    #
    # ONE COMPONENT, DRAWN WHERE THE BLOCK'S OWN ELEMENT IS: inside the card
    # of a block of the page's list (`Admin::BlockCardComponent`), and inside
    # the TILE of a block in a section's column (`BlockTileComponent`) --
    # not in that block's form panel, where it used to be. A panel is `hidden`
    # until its tile is pressed, and a `<dialog>` inside a hidden element is
    # not drawn when it is opened: "Delete block…" in the tile's menu would
    # have done nothing while the form was closed. Opening the form first to
    # delete the block would close whichever form was open, for a block that
    # is about to go.
    #
    # In the element that stands for the block, the dialog can never be left
    # behind: every answer that removes or redraws that element -- a delete
    # (`remove`), a move between the list and a column (`replace`), a
    # section's lanes or the whole list redrawn -- takes the dialog with it
    # and, where the block stays, brings its new one. Nothing streams the
    # dialog by itself. An unavailable block's panel still has "Delete block…"
    # in it (the block's one action): it names this dialog by id, in the tile.
    #
    # The confirm is a form of its own; neither a card nor a tile puts it
    # inside another form.
    class DeleteBlockDialogComponent < AdminComponent
      def self.dialog_id(block) = "delete-block-#{block.id}"

      def initialize(page:, block:, url_options: {})
        @page = page
        @block = block
        @url_options = url_options
      end

      def dialog_id = self.class.dialog_id(block)

      def destroy_path = helpers.admin_page_content_block_path(page, block, **url_options)

      private

      attr_reader :page, :block, :url_options
    end
  end
end
