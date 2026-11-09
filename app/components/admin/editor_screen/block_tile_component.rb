module Admin
  module EditorScreen
    # A block inside a section, as it stands in its column: its type (chip and name) over its
    # preview or its one line (`TileSummaryComponent`), on a button that opens the block's form
    # under the lanes (`admin--editor--section#toggle`). Its states -- under the pointer, open or
    # focused, dragged, its thread open -- are the stylesheet's (`.admin-block-tile`), drawn by
    # elevation.
    #
    # THE TILE HAS THE BLOCK'S `dom_id`, as a card of the block list has: it
    # is the element that stands for the block where the block is, the one a
    # lane's order is read from and a delete removes. The form is elsewhere
    # -- `Admin::EditorScreen::BlockCardComponent`'s `placement: :panel`, under its own
    # `panel_id` -- and the face names it with `aria-controls`.
    #
    # The face is a real button, so a tile is opened by Enter and Space and
    # is in the Tab order; `aria-expanded` says whether its form is the open
    # one and is kept by `admin--editor--section`. `open:` is for a tile rendered
    # while its form is to be shown at once (a block just added): the script
    # opens the panel, and the tile must not say "collapsed" in between.
    #
    # THE GRIP IS FOR THE POINTER ONLY: a `<span>` hidden from a screen reader, not the `<button>` a
    # card's handle is. A card's handle is also its keyboard path (Space, arrows, Space), which
    # moves a card along one list; a tile's moves are along its lane, to another column and out of
    # the section, and those are items of the tile's menu, where each has a name. A focusable grip
    # beside the face would be a second stop on every tile for a control the keyboard can't work.
    # Only for a viewer who can edit, as a card's handle is.
    #
    # THE "⋯" MENU IS THE TILE'S KEYBOARD PATH, for a viewer who can edit: Move up and Move down
    # along the lane (the card's own buttons, `data-move` and
    # `admin--editor--blocks#moveUp|moveDown`), "Move to column…" (the page's one Move dialog,
    # `MoveDialogComponent`), "Move out of section" (`admin--editor--blocks#moveOut`: to the page's
    # list, directly after the section), Duplicate, and "Delete block…". Every move item is rendered
    # enabled: which of them has nowhere to go -- the first tile's Move up, the last one's Move
    # down, "Move to column…" in a section of one column -- depends on the tile's neighbours and its
    # section's layout, which change without the tile being drawn again, so
    # `admin--editor--blocks#refreshMoveState` says it, as the tile connects and after every change
    # of a lane.
    #
    # A tile of a type that is not registered any more keeps the four moves and "Delete block…", and
    # has no Duplicate: nothing of it can be read, so it is not copied. Delete is its only action on
    # the block itself; but the tile keeps its grip, so the pointer moves it along its lane, to
    # another column and out of the section, and the keyboard has whatever the pointer has.
    #
    # In a section whose own type is gone the tile is drawn the same and `admin--editor--blocks`
    # disables what cannot be done there -- Move up, Move down and "Move to column…", since that
    # section has no column the server would take a block into (`admin--editor--blocks#closed`).
    # "Move out of section" and "Delete block…" are what is left, and no Duplicate (`duplicate?`).
    #
    # THE BLOCK'S DELETE DIALOG IS IN THE TILE (`DeleteBlockDialogComponent`,
    # which says why it is not in the form's panel). It is a child of the
    # tile and not of the lane: a lane's children are exactly its tiles.
    #
    # A viewer who can't edit may still open a tile: the form they get is the
    # disabled one a view-only card shows. They get the face, the notes marker (whoever can read the
    # page writes notes) and a "⋯" menu whose only item is "Add note", and nothing else. For an
    # editor "Add note" is the first item of the tile's menu.
    class BlockTileComponent < AdminComponent
      include HeldUnit

      def initialize(page:, block:, locale:, url_options: {}, editable:, open: false, holds: nil)
        @page = page
        @block = block
        @locale = locale
        @url_options = url_options
        @editable = editable
        @open = open
        @holds = holds
      end

      def dom_id = ActionView::RecordIdentifier.dom_id(block)

      def label = block.definition&.label || block.block_type

      def panel_id = Admin::EditorScreen::BlockCardComponent.panel_id(block)

      # The face's name is the type and the preview's heading (or the one
      # line), with the attention mark and "Needs fixing" when they are
      # drawn; the preview's few lines of text are its description, so a
      # screen reader says what the tile is before it reads what it holds.
      def type_id = "#{dom_id}-type"

      def labelled_by = [ type_id, *TileSummaryComponent.part_ids(block) ].join(" ")

      def described_by = TileSummaryComponent.text_id(block)

      def open? = @open

      def editable? = @editable

      # The tile stands for a block the panel of which is read-only while
      # someone else holds it: it says so in its version (a catch-up redraws
      # it when the hold comes or goes) and in `data-editing-held`. The avatar
      # of the holder stands in the slot `editor.block.markers`.
      # `HeldUnit` answers for the block on its page; a tile uses its `held?`
      # and its `editing_version` and draws no strip, no form and no menu item.
      def held_subject = block

      def held_record = page

      def unavailable? = block.definition.nil?

      # Whether the menu offers Duplicate. Not for a type that is not
      # registered any more: nothing of it can be read to copy. And not in a section
      # whose own type is gone: a copy goes into its source's
      # column, and that section has no column left to take one
      # (`ContentBlock#section_rules`), so the item could only fail. Its
      # blocks are moved out or deleted, as its card says.
      def duplicate? = !unavailable? && block.section&.container?

      def duplicate_path = helpers.duplicate_admin_page_content_block_path(page, block, **url_options)

      def delete_dialog = Admin::EditorScreen::DeleteBlockDialogComponent.new(page: page, block: block, url_options: url_options)

      def delete_dialog_id = Admin::EditorScreen::DeleteBlockDialogComponent.dialog_id(block)

      # IN THE TEMPLATE, with no method here any more (the slot loads nothing).
      # The block's markers (slot `editor.block.markers`: the holder's avatar,
      # then the notes marker): on the tile, never on the block's form panel,
      # and for every viewer. A slot for one block: nothing is loaded for it,
      # and the page's holds, read already, go to it as context (`holds:`).

      def note_key = ::Notes.key(block)

      # A type whose icon follows its block (the Note's kind) shows the block's own.
      # The chip stands before the type's name on the face's first line; it
      # is `aria-hidden`, so the face's accessible name and the move
      # announcement read the name. A type with no icon shows its name alone.
      def block_icon = @block_icon ||= Admin::Ui::BlockIconComponent.new(definition: block.definition, place: :tile, block: block)

      def icon? = block_icon.render?

      # "Add note": first in an editor's menu, and the only item of the menu
      # a view-only tile has (see `Admin::EditorScreen::BlockCardComponent#add_note_item`).
      def add_note_item
        tag.button(t(".add_note"), type: "button", class: menu_item_class, data: { action: "admin--notes--drawer#open", notes_key: note_key, notes_compose: true })
      end

      def move_to_column = Admin::EditorScreen::MoveDialogComponent.trigger("column")

      def menu_item_class = Admin::EditorScreen::BlockCardComponent::MENU_ITEM_CLASS

      private

      attr_reader :page, :block, :locale, :url_options
    end
  end
end
