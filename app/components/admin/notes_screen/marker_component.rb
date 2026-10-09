module Admin
  module NotesScreen
    # The notes marker of one block (notes spec §4.3), on its card or tile.
    # With open threads: a neutral pill with their number (§4.5: accent is
    # for "unread and addressed to you" only). Without: nothing at rest --
    # the system shows no count at zero -- and the same control as "add a
    # note" while the pointer is over the card or the keyboard's focus is in
    # it. "Add note" in the block's ⋯ menu is the path that depends on
    # neither.
    #
    # The server draws it WITHOUT a number: a card is drawn by the page and by
    # every stream that adds, moves or redraws a block, and none of them
    # should cost a query for a count. `admin--notes` fills it from the
    # record's counts when it connects (`data-has-notes`, `data-unread`, the
    # number, the label), and turns it into "Note on selection" while text is
    # selected in that block's rich text. So a marker drawn again by a stream
    # reads right without the server knowing a count at all.
    #
    # Its look is `.admin-notes-marker` in content-spiel.tailwind.css, not a
    # list of utilities here: it has four states (at rest, shown, a count,
    # unread) in two sizes (a card's and a tile's), and the size follows from
    # where it stands, so one component draws both.
    #
    # In the document for everyone who can read the page, whether or not they
    # can edit it (decision D3); a test presses the menu item or focuses the
    # marker, never waits for a hover.
    class MarkerComponent < Admin::AdminComponent
      def initialize(subject:, name:)
        @subject = subject
        @name = name
      end

      private

      attr_reader :name

      def key = ::Notes.key(@subject)
    end
  end
end
