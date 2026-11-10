module Admin
  module NotesScreen
    # The image's notes on the Media screen, registered at
    # the rail's panel slot `media.rail.tabs`
    # (`config/initializers/admin_slots.rb`): the Notes tab after Image, so
    # the screen and its rail do not name notes. What it answers the slot:
    # `tab_key` "notes", the tab's label, the open count (a `total` of
    # `admin--notes--drawer` that says "2 new" while something is unread),
    # and `tab_current?` for an address that asks for the notes.
    #
    # ONE ELEMENT AT EVERY WIDTH. Where the rail docks it is the Notes tab's
    # panel and its heading is hidden (the tab names it); below that the
    # rail draws no tabs and every panel stands in the page, so it is the
    # section at the panel's end, under its heading. Either way there is one
    # `turbo-frame#notes` in the page, the same frame the editors' Notes tab
    # shows, and a thread opens in place where the list was.
    #
    # It stands OUTSIDE the image's autosave form: the frame brings forms of
    # its own, a form cannot nest, and inside an `admin--saving--autosave`
    # form a note's field would be the image's. Anyone who may open the
    # panel may read and write notes there (`media.upload`,
    # `Admin::NoteContainer`), whether or not the image is theirs to edit;
    # that is `render?` (`Notes.readable?` asks the registry's read right for
    # an image), true wherever the panel is shown.
    class MediaSectionComponent < Admin::AdminComponent
      def initialize(record:, viewer:, data: nil, url_options: {}, query: nil, **)
        @asset = record
        @viewer = viewer
        @url_options = url_options || {}
        @query = query || {}
      end

      def render? = ::Notes.readable?(viewer, asset)

      def tab_key = "notes"

      # Asked before the component is rendered (the tablist is drawn first),
      # so by its whole key: a relative one needs a view context.
      def tab_label = ::I18n.t("admin.components.notes_screen.rail_panel.tab")

      def tab_count = note_counts.fetch("total").to_i

      # The tab's number is a `total` of `admin--notes--drawer`, like the
      # heading's, and says "2 new" while something is unread for the viewer.
      def tab_count_data = { "admin--notes--drawer-target": "total", notes_total_words: true }

      # `?notes=open`, or a thread to start on (a link from the inbox): the
      # Notes tab is drawn current, so the first paint shows the notes.
      def tab_current? = @query["notes"] == "open" || thread.present?

      # The image's notes: `view: "media"` travels with every request of the
      # frame, so a thread started here records where it was written;
      # `thread` (`/media?selected=<id>&thread=<id>`) starts the frame on that
      # thread's view instead of the list.
      def notes_path
        options = { view: "media", **url_options }
        thread ? helpers.admin_record_note_thread_path("media", asset.id, thread, **options) : helpers.admin_record_notes_path("media", asset.id, **options)
      end

      # The image's counts as the page loaded them (`#notes-counts`), which
      # `admin--notes--drawer` on <body> reads; every answer of the frame brings a
      # newer copy. Read here and not left to the frame, because that
      # controller keeps the last counts it saw: the panel of the image chosen
      # next would show the last image's number until its own frame had loaded.
      def note_counts = @note_counts ||= ::Notes::Counts.for_container(asset, user: ::Notes.user_of(viewer))

      # "Notes · 2 open" (in mono capitals). The number is an
      # `admin--notes--drawer` `total`, like the tab's, so it follows a note
      # added or resolved in the frame below.
      def notes_open
        total = note_counts.fetch("total").to_i
        t(".notes_open_html", number: tag.span(total, hidden: total.zero?, data: { "admin--notes--drawer-target": "total" }))
      end

      private

      attr_reader :asset, :viewer, :url_options

      # Digits or nothing: it becomes a path segment.
      def thread = @query["thread"].to_s[/\A\d+\z/]
    end
  end
end
