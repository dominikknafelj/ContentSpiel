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

      # The element that stands for the block (its card or its tile): the
      # warning below counts the open notes of the markers inside it, and the
      # block's own.
      def within_id = ActionView::RecordIdentifier.dom_id(block)

      # The dialog's warning about open notes (notes spec D12), for this
      # dialog and for a section's: an empty, hidden paragraph that
      # `admin--notes` fills and shows while what `within` names has open
      # threads. The look is the warn alert's (`border-warn bg-warn-tint`).
      # The server writes no number into it, for the reason a marker holds
      # none (`Admin::NotesScreen::MarkerComponent`).
      # `spacing:` is for a dialog that says something else above it (a
      # section's). `alone:` is for this one, where the warning is all its
      # box holds: `data-notes-alone` lets the stylesheet take the box out of
      # the layout while the warning is hidden, so a block without notes has
      # no empty room in its dialog. The mark is on the warning, and the rule
      # asks for it by name, so no other dialog's box can be hidden by it.
      NOTES_WARNING_CLASS = "rounded-cs border border-warn bg-warn-tint px-3 py-2 text-sm text-ink".freeze

      #
      # `kind:` picks the sentence: a block's ("This block has 2 open notes.
      # They will be deleted with it."), or `:section` for a section deleted
      # with its blocks ("This section and its blocks have 3 open notes. They
      # will be deleted too."), whose number is the open notes on the blocks
      # inside it: a section takes none of its own (the handoff's decision 10).
      def self.notes_warning_attributes(within, spacing: nil, alone: false, kind: :block)
        { hidden: true, class: [ NOTES_WARNING_CLASS, spacing ],
          data: { "admin--notes-target": "warning", notes_within: within, notes_warning: kind, **(alone ? { notes_alone: "" } : {}) } }
      end

      def destroy_path = helpers.admin_page_content_block_path(page, block, **url_options)

      private

      attr_reader :page, :block, :url_options
    end
  end
end
