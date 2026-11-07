module Admin
  module NotesScreen
    # The Notes tab of an editor's rail (notes spec §4.1), registered at the
    # panel slot `editor.rail.tabs` (`config/initializers/admin_slots.rb`):
    # the rail draws its tab after its own and this as the content of its
    # panel (`Admin::Ui::RailSlotComponent`), so the editors and the rail do
    # not name notes. What it answers the slot: `tab_key` "notes", the tab's
    # label, the open count, and `render?` for a page or a post whose notes
    # the viewer may read.
    #
    # ONE ELEMENT AT EVERY WIDTH. The panel is rendered once and is never
    # cloned, moved or drawn again (a save's answer replaces the tab only),
    # so a note being typed in it survives a tab switch, the rail docking or
    # undocking, and a live merge. Where the rail docks it is the Notes tab's
    # content; below the threshold, while the tab is current, the stylesheet
    # makes the same element a 400px slide-over from the right over the
    # canvas, and under 640px a full-screen sheet with "Back to <title>"
    # (content-spiel.tailwind.css, "THE NOTES PANEL"). Neither is modal:
    # nothing is made inert, no scrim, and Escape closes it only while the
    # focus is inside (the `keydown.esc` action sits here).
    #
    # Outside every form: the frame brings forms of its own, forms can't
    # nest, and inside an `admin--saving--autosave` form a note's field would
    # be the record's. The rail's panels stand outside the post form, as
    # siblings of it in the grid.
    #
    # It holds the notes frame empty: `admin--notes--drawer` sets the frame's
    # `src` (`data-src`, plus the thread or the block to start on) when the
    # notes are first shown, so an editor that never shows its notes never
    # fetches them. `#notes-counts` is the record's counts as the page loaded
    # them; every answer of the frame brings a newer copy. `?notes=open`, and
    # `?thread=` with it, in the request's query (the slot's `query:`) opens
    # the tab on load at that thread.
    #
    # Its header is the LIST's: the title, how many are open (an
    # `admin--notes--drawer` `total`, like the header button's and the tab's,
    # so it follows the counts), "New note" -- a note on the record itself --
    # and Close. While a thread is the view it is not shown, and the thread's
    # first row is the header, with a Close of its own (the handoff's
    # decisions 11 and 17; the stylesheet's "THE THREAD VIEW'S HEADER"). The
    # sheet (under 640px) has "Back to <title>" in Close's place, and over a
    # thread its first row ends in "Back to page", the same action.
    class RailPanelComponent < Admin::AdminComponent
      def initialize(record:, viewer:, data: nil, locale: nil, url_options: {}, query: nil, reads: nil, **)
        @record = record
        @viewer = viewer
        @locale = locale
        @url_options = url_options || {}
        @query = query || {}
        @reads = reads
      end

      def render?
        (record.is_a?(::Page) || record.is_a?(::Post)) && record.persisted? && ::Notes.readable?(viewer, record)
      end

      def tab_key = "notes"

      # Asked before the component is rendered (the tablist is drawn first),
      # so by its whole key: the relative `t(".tab")` needs a view context.
      def tab_label = ::I18n.t("admin.components.notes_screen.rail_panel.tab")

      # The open threads, from the screen's one read of the counts. A save's
      # stream hands no `reads:` and reads nothing: the tab is drawn with its
      # number hidden, and as it connects `admin--notes--drawer` fills it from
      # the counts this tab already holds, as it fills a marker a stream drew.
      def tab_count = counts ? counts.fetch("total").to_i : 0

      # The tab's number is a `total` of `admin--notes--drawer`.
      def tab_count_data = { "admin--notes--drawer-target": "total" }

      # `?notes=open` in the request: the Notes tab is drawn current, so the
      # first paint shows the notes and not the host's own tab first.
      def tab_current? = open?

      def open? = @query["notes"] == "open"

      private

      attr_reader :record, :viewer

      # The screen's read, or nil: a host that hands no `reads:` gets a panel
      # with no counts at all (no `#notes-counts`, no figures), never zeros,
      # which `admin--notes--drawer` would take for the truth and clear every
      # marker and the header's number with.
      def counts
        return @counts if defined?(@counts)

        @counts = CountsComponent.read(record, viewer:, reads: @reads)
      end

      def title = ::Locales.read(record, :title, locale: @locale.presence || ::Locales.default).presence || t(".untitled")

      def src = helpers.admin_record_notes_path(*helpers.note_args(record), **@url_options)

      def key = ::Notes.key(record)

      # The address of the editor this panel belongs to, without its query:
      # `admin--notes--drawer` writes `notes=open` into the page's address
      # only while the address is this one (`syncAddress`). The record's own
      # screen, by the route its kind has (`Audit::Sentence.route_for`),
      # resolved from the notes' list of routes like every other.
      def path = helpers.note_route_path(::Audit::Sentence.route_for(record))

      # Digits or nothing: it becomes a path segment in the script.
      def thread = @query["thread"].to_s[/\A\d+\z/]

      def total = tab_count

      # "4 open" beside the title. The number is a span the script rewrites;
      # the word around it is the locale file's.
      def open_count
        number = tag.span(total, hidden: total.zero?, data: { "admin--notes--drawer-target": "total" })
        t(".open_html", number: number)
      end
    end
  end
end
