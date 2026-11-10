module Admin
  module Ui
    # The find field at the top of a tree column, and its status line: what a
    # person types narrows the tree it names (`controls:`, the tree's id) to
    # the rows that match and their ancestors, with the matched text marked.
    # A query starting with "/" matches a page's address instead of its
    # title. The narrowing is the browser's, over the rows the tree drew
    # (`tree/find.js` under `admin--tree--find`); the server draws only the
    # field, empty.
    #
    # `noun:` picks the words for what the tree holds: `:pages` (Pages), or
    # `:nodes` (the mind graph's list, which holds posts and tags too).
    # `moving:` says the tree's rows move by drag, which is off while the
    # tree is narrowed, so a sentence under the status line then says how to
    # move them again.
    #
    # The script talks to the tree by events and owns the keys of a find:
    # "/" from anywhere but a text field, Down Arrow to the first match, Up
    # Arrow back, Enter to open the first match, and Escape to clear (not
    # taken in an empty field, so a drawer's own Escape still closes it).
    class TreeFindComponent < AdminComponent
      include Admin::Ui::Contract

      NOUNS = %i[pages nodes].freeze

      contract(
        accessibility: "A search landmark round a search field with a real label, naming the tree it narrows and its shortcut, the slash; a polite status line says the count once the typing stops, in one line of room kept from the first key; where the tree moves, “Clear the search to move pages” shows under it with the narrowing, outside the live region, and is the field's aria-describedby while it shows; Down Arrow reaches the first match and Escape clears.",
        motion: :reduced,
        content_edges: %i[short long],
        widths: :fluid,
        interface: %i[controls noun moving keep_across_frames],
        limits: [
          "It narrows only the rows the tree drew: a page the tree does not draw is not found.",
          "The narrowing is never stored: a branch it opens folds again when the field is cleared, and the open set is unchanged.",
          "A tree that moves by drag does not move while narrowed, and a sentence under the status line says so.",
          "With keep_across_frames the query outlives a navigation of the content frame (its tree is drawn again and narrowed by it); a visit of the whole page always empties the field."
        ],
        states: %i[rest focus],
        script_states: {
          filled: [ "test/system/admin/tree_find_test.rb", "typing narrows the tree to matches and their paths, marks them, and Escape gives back the person's folds" ],
          filtered: [ "test/system/admin/tree_find_test.rb", "typing narrows the tree to matches and their paths, marks them, and Escape gives back the person's folds" ],
          no_match: [ "test/system/admin/tree_find_test.rb", "no match says No pages match, and no tree is shown" ]
        },
        keys: %w[label.pages label.nodes placeholder.pages placeholder.nodes count.pages count.nodes none.pages none.nodes no_moving clear],
        slots: [],
        controller: "admin--tree--find",
        keyboard: [ "test/system/admin/tree_find_test.rb", "/ focuses the field, Down Arrow reaches the first match, Enter opens it" ]
      )

      def initialize(controls:, noun: :pages, moving: false, keep_across_frames: false)
        raise ArgumentError, "a find field names the tree it narrows: give controls:" if controls.blank?
        raise ArgumentError, "unknown noun #{noun.inspect}: one of #{NOUNS.join(', ')}" unless NOUNS.include?(noun)

        @controls = controls
        @noun = noun
        @moving = moving
        @keep_across_frames = keep_across_frames
      end

      private

      attr_reader :controls, :noun, :moving, :keep_across_frames

      def field_id = "#{controls}-find"

      # The status line's room while the field holds a query: one line of its
      # own type (`lh`), the count. Kept from the first key, so the count
      # written after the typing stops moves nothing below it.
      def reserve_class = "min-h-[1lh]"

      # "Clear the search to move pages", the field's description while shown.
      def moving_id = "#{field_id}-moving"

      # The words the script writes into the status line: this noun's.
      def script_messages
        messages_data("components.ui.tree_find.count.#{noun}", "components.ui.tree_find.none.#{noun}")
      end
    end
  end
end
