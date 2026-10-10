module Admin
  module NotesScreen
    # The image's notes in the media library's side panel (notes spec §4.4),
    # registered at the panel's `media.panel.sections` slot
    # (`config/initializers/admin_slots.rb`): the same frame the editors'
    # drawer shows, in place -- this screen has no drawer, so a thread opens
    # where the list was. It stands OUTSIDE the panel's autosave form: the
    # frame brings forms of its own, a form cannot nest, and inside an
    # `admin--saving--autosave` form a note's field would be the image's.
    # Anyone who may open the panel may read and write notes there
    # (`media.upload`, `Admin::NoteContainer`), whether or not the image is
    # theirs to edit; that is `render?` (`Notes.readable?` asks the registry's
    # read right for an image), true wherever the panel is shown.
    class MediaSectionComponent < Admin::AdminComponent
      def initialize(record:, viewer:, data: nil, url_options: {}, **)
        @asset = record
        @viewer = viewer
        @url_options = url_options
      end

      def render? = ::Notes.readable?(viewer, asset)

      # The image's notes: `view: "media"` travels with every request of the
      # frame, so a thread started here records where it was written;
      # `thread` (a link from the inbox, `/media?selected=<id>&thread=<id>`)
      # starts the frame on that thread's view instead of the list. Digits or
      # nothing: it becomes a path segment.
      def notes_path
        options = { view: "media", **url_options }
        thread = helpers.params[:thread].to_s[/\A\d+\z/]
        thread ? helpers.admin_record_note_thread_path("media", asset.id, thread, **options) : helpers.admin_record_notes_path("media", asset.id, **options)
      end

      # The image's counts as the page loaded them (`#notes-counts`), which
      # `admin--notes--drawer` on <body> reads; every answer of the frame brings a
      # newer copy. Read here and not left to the frame, because that
      # controller keeps the last counts it saw: the panel of the image chosen
      # next would show the last image's number until its own frame had loaded.
      def note_counts = @note_counts ||= ::Notes::Counts.for_container(asset, user: ::Notes.user_of(viewer))

      # "Notes · 2 open" (in mono capitals, the handoff's header). The number
      # is an `admin--notes--drawer` `total`, like the one beside the drawer's title,
      # so it follows a note added or resolved in the frame below.
      def notes_open
        total = note_counts.fetch("total").to_i
        t(".notes_open_html", number: tag.span(total, hidden: total.zero?, data: { "admin--notes--drawer-target": "total" }))
      end

      private

      attr_reader :asset, :viewer, :url_options
    end
  end
end
