module Admin
  module NotesScreen
    # The list view of the notes frame (notes spec §4.2), top to bottom:
    # Pinned, Open by group, Resolved (collapsed, loaded when opened), or the
    # shared empty state with "New note". The same list in the editors' drawer
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
      # itself (Task 6 draws the field).
      def new_note_path = helpers.admin_record_notes_path(*helpers.note_args(container), **frame_params(compose: key))
    end
  end
end
