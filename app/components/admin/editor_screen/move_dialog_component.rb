module Admin
  module EditorScreen
    # "Move block": where a block goes when it is moved from its menu
    # (sections spec §4.4) -- a tile's "Move to column…" and a top-level
    # card's "Move into section…". The keyboard path for what a drag between
    # containers does.
    #
    # ONE DIALOG FOR THE PAGE, AND ITS CHOICES ARE NOT RENDERED HERE (sections
    # plan, D10). The `<select>` is empty: `admin--blocks#askWhere` fills it,
    # as the dialog opens, from the sections and lanes on the screen. Sections
    # are added, removed and given other layouts without any other card being
    # drawn again, so a list of destinations written by the server -- here, or
    # in each card's menu -- would be stale after the first such change.
    #
    # It sits inside the Blocks section of the page editor, not in the layout
    # with the dialogs that hold a form: it holds none (Cancel and the header's
    # × are `method="dialog"`, which never leaves the page), and it has to be
    # inside `admin--blocks`' element for the `destination` target and the
    # Move button's action to be that controller's.
    #
    # `trigger` is the `data:` of a menu item that opens it: one click, two
    # actions in this order. `admin--blocks#askWhere` first -- it notes which
    # block is being moved and writes the choices -- then `admin--ui--dialog#open`,
    # so the dialog is shown the way every dialog is: the focus goes to its
    # first field, the select, and comes back to the menu's button when it is
    # closed without a move (`admin--ui--dialog#returnFocus`). `move` is the
    # item's `data-move`, by which `admin--blocks#refreshMoveState` finds it
    # to disable it while there is nowhere to go.
    #
    # The two option labels the script writes (`column`, `section_column`)
    # are served by the `data-messages` of the Blocks section around it
    # (`admin/pages/show`), as literals: `test/lib/script_messages_test.rb`
    # reads them there.
    class MoveDialogComponent < AdminComponent
      ID = "move-block-dialog".freeze
      DESTINATION_ID = "move-block-destination".freeze

      def self.trigger(move)
        { move: move, action: "click->admin--blocks#askWhere admin--ui--dialog#open", "admin--ui--dialog-id-param": ID }
      end

      def dialog_id = ID

      def destination_id = DESTINATION_ID
    end
  end
end
