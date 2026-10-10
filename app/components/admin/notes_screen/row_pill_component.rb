module Admin
  module NotesScreen
    # The open-notes pill of a row in a list (notes spec §4.4, §4.5), registered
    # at the `tree.row.markers` and `posts.row.markers` slots
    # (`config/initializers/admin_slots.rb`). One component for both lists
    # because the data is the same; the MARKUP is not, so it has two variants,
    # picked by the record, each byte-for-byte what its list drew before the
    # slots:
    # - a page (the tree): a readonly span at the tile's size with the icon.
    #   It is no link of its own: the row's title opens the page, and its notes
    #   are one press on the header's button from there;
    # - a post (the posts list): the pill without an icon, a link that opens
    #   the post with its drawer open (`?notes=open`), `no-underline`, it is a
    #   pill and not text.
    # Neutral; accent (`data-unread`) only while something there is unread and
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
          unread = ::Notes::Counts.unread_among(type, ids, viewer)
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

      def post_path = helpers.admin_post_path(@record, **@url_options.merge(notes: "open"))
    end
  end
end
