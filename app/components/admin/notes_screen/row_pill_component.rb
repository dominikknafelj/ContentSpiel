module Admin
  module NotesScreen
    # The open-notes pill of a row in a list, registered at the
    # `tree.row.markers` and `posts.row.markers` slots
    # (`config/initializers/admin_slots.rb`). The loader and the words are
    # notes'; the drawing is the shared `Admin::Ui::NoteMarkerComponent`. One
    # component for both lists because the data is the same; the variant is
    # picked by the record:
    # - a page (the tree): the small readonly image. It is no link of its
    #   own: the row's title opens the page, and its notes are one press on
    #   the header's button from there;
    # - a post (the posts list): a link that opens the post with its drawer
    #   open (`?notes=open`).
    # Unread (`data-unread`) only while something there is unread and
    # addressed to the viewer; nothing at zero.
    #
    # `data` is `{ open:, unread: }` from the loader, which reads the counts
    # ONCE for every row the list draws (`Notes::Counts.by_container`, and
    # `unread_among` beside it), so a row costs no query of its own.
    class RowPillComponent < Admin::AdminComponent
      # The loader for a list of `type` ("Page", "Post"): the two reads each
      # list made itself before the slots, with the same arguments. `Notes::
      # Counts` hides nothing itself: the rows are the ones the list already
      # narrowed through the read scope.
      def self.loader(type)
        lambda do |records, viewer:|
          ids = records.map(&:id)
          counts = ::Notes::Counts.by_container(type, ids)
          unread = ::Notes::Counts.unread_among(type, ids, ::Notes.user_of(viewer))
          records.to_h { |record| [ record.id, { open: counts.fetch(record.id, 0), unread: unread.include?(record.id) } ] }
        end
      end

      def initialize(record:, viewer:, data: nil, url_options: {}, **)
        @record = record
        @data = data
        @url_options = url_options
      end

      def render? = open_notes.positive?

      def open_notes = @data ? @data.fetch(:open).to_i : 0

      def unread? = @data ? @data.fetch(:unread) : false

      def post? = @record.is_a?(::Post)

      # The bubble's name: its count, and "new for you" while any of it is.
      def label = unread? ? t(".open_notes_unread", count: open_notes) : t(".open_notes", count: open_notes)

      def post_path = helpers.admin_post_path(@record, **@url_options.merge(notes: "open"))
    end
  end
end
