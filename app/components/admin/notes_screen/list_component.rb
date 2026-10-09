module Admin
  module NotesScreen
    # The list view of the notes frame (notes spec §4.2), top to bottom:
    # Pinned, Open by group, Resolved (collapsed, loaded when opened), or the
    # shared empty state with "New note"; above them, when it was asked for
    # (`?compose=<key>`, what "New note" and a block's "Add note" open) or
    # when a new note just failed, the field for a new note (`#notes-new`), on
    # the record or on the block the key names. The same list in the editors' drawer
    # and in the media panel. It carries the record's counts for
    # `admin--notes`, so every answer of the frame also corrects the header's
    # number and the markers.
    class ListComponent < Admin::AdminComponent
      def initialize(listing:, viewer:, locale:, view:, type:, compose: nil, failed: nil, notice: nil)
        @listing = listing
        @viewer = viewer
        @locale = locale
        @view = view
        @type = type
        @compose = compose.to_s.presence
        @failed = failed
        @notice = notice
      end

      private

      attr_reader :listing, :viewer, :locale, :view, :type, :compose, :failed, :notice

      def container = listing.container

      def key = ::Notes.key(container)

      def row(record, show_subject: false)
        Admin::NotesScreen::ThreadRowComponent.new(thread: record, listing: listing, viewer: viewer, type: type, view: view, show_subject: show_subject)
      end

      def group_title(group) = helpers.note_subject_name(group.subject, container, type)

      def empty? = listing.open_count.zero? && listing.resolved_count.zero?

      def frame_params(**extra) = { view: (view unless view == "editor"), **helpers.admin_url_options, **extra }.compact

      def more_path = helpers.admin_record_notes_path(*helpers.note_args(container), **frame_params(limit: listing.next_limit))

      def resolved_path = helpers.admin_resolved_record_notes_path(*helpers.note_args(container), **frame_params)

      # "New note": the list again, with the field for a note on the record
      # itself.
      def new_note_path = helpers.admin_record_notes_path(*helpers.note_args(container), **frame_params(compose: key))

      # --- the new note --------------------------------------------------------

      def failed_new = (failed if failed && failed[:key] == "new")

      def composing? = compose.present? || failed_new.present?

      # The passage the new note quotes (decision D4): from the failed form, or
      # from the URL the opener built. A copy, cut to the column's length.
      #
      # In the URL its name is `note_quote`, never `quote`: a GET's query
      # string is written to the log, and `note_quote` is a name that can be
      # filtered there wherever it appears (`config/initializers/
      # filter_parameter_logging.rb`). The form then posts it as `quote`.
      def quote = (failed_new ? failed_new[:quote] : helpers.params[:note_quote]).to_s.strip.first(::Notes::Thread::MAX_QUOTE).presence

      # What the new note is on: the block the URL (or the failed form) names,
      # when it is one of this record's; otherwise the record itself.
      def compose_subject = listing.subject_by_key(failed_new ? failed_new[:subject] : compose) || container

      # The form's `subject`: blank for the record itself.
      def compose_key = compose_subject == container ? "" : ::Notes.key(compose_subject)

      def compose_title
        return t(".new_on.#{type}") if compose_subject == container

        # The block as its group's heading names it, column included: plain
        # text, escaped once by the template.
        t(".new_on_block", block: helpers.note_subject_name(compose_subject, container, type))
      end

      def threads_path = helpers.admin_record_note_threads_path(*helpers.note_args(container), **frame_params)

      def mentions_path = helpers.admin_record_note_mentions_path(*helpers.note_args(container))
    end
  end
end
