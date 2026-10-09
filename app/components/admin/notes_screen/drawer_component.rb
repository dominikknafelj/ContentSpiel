module Admin
  module NotesScreen
    # The notes drawer of an editor (notes spec §4.1; the handoff's decision 1
    # of 2026-10-09): from 1024px a 400px COLUMN to the right of the content
    # and below the editor's sticky header -- surface background, a 1px line
    # on its left edge, no shadow, no scrim, no page lock. It takes its room
    # from the content column, so nothing of the editor is under it, and the
    # page tree folds into its drawer while it is open (both in
    # content-spiel.tailwind.css, "The editors' notes drawer"). Below 1024px
    # it is a full-screen sheet under the top bar with "Back to <title>"
    # (nothing is designed below 768px). The editor beside it stays usable.
    # Rendered once per screen, inside `#content` (a frame navigation to
    # another record replaces it) and OUTSIDE EVERY FORM: the frame brings
    # forms of its own, forms can't nest, and inside an `admin--autosave` form
    # a note's field would be the record's. `hidden` until `admin--notes`
    # opens it.
    #
    # It holds the notes frame empty: the controller sets the frame's `src`
    # (`data-src`, plus the thread or the block to start on) when the drawer
    # first opens, so an editor that never opens its notes never fetches them.
    # `#notes-counts` is the record's counts as the page loaded them; every
    # answer of the frame brings a newer copy.
    #
    # Its header is the LIST's: the title, how many are open (the number is
    # an `admin--notes` `total`, like the header button's, so it follows the
    # counts), "New note" -- a note on the record itself, no chooser -- and
    # Close. While a thread is the view it is not shown, and the thread's
    # first row is the header, with a Close of its own (the handoff's
    # decision 11; the stylesheet's "THE THREAD VIEW'S HEADER"). The sheet has
    # "Back to <title>" in Close's place, and keeps its header over a thread
    # too: that button is the sheet's one way back to the editor.
    #
    # WHEN TO USE WHICH: the shell's left drawers (`admin--drawer`) are the
    # navigation at narrow widths, with a scrim; the media panel is a column
    # of its screen, in the flow; this is a companion to an editor that must
    # not take the editor away.
    class DrawerComponent < Admin::AdminComponent
      def initialize(container:, counts:, title:, view: "editor", open: false, thread: nil, url_options: {})
        @container = container
        @title = title
        @counts = counts
        @view = view
        @open = open
        # Digits or nothing: it becomes a path segment in the script.
        @thread = thread.to_s[/\A\d+\z/]
        @url_options = url_options
      end

      private

      attr_reader :container, :counts, :thread, :title

      def src = helpers.admin_record_notes_path(*helpers.note_args(container), **{ view: (@view unless @view == "editor"), **@url_options }.compact)

      def key = ::Notes.key(container)

      def open? = @open ? true : false

      def total = counts.fetch("total").to_i

      # "4 open" beside the title. The number is a span the script rewrites;
      # the word around it is the locale file's.
      def open_count
        number = tag.span(total, hidden: total.zero?, data: { "admin--notes-target": "total" })
        t(".open_html", number: number)
      end
    end
  end
end
