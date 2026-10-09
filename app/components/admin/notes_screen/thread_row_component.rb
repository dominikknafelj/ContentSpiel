module Admin
  module NotesScreen
    # One thread as a row of the list (notes spec §4.2): the first message's
    # author, time and first line, the reply count, and "new" in accent while
    # it holds a delivery the viewer has not read -- the one meaning accent
    # has here (§4.5). A link into the notes frame: following it replaces the
    # list with the thread.
    #
    # Unread is said three ways, never by colour alone: the name is heavier,
    # the first line is ink, not dim, and the last line reads "new"; the
    # accent dot at the right edge repeats it. A pinned row has a pin where
    # the dot would be.
    class ThreadRowComponent < Admin::AdminComponent
      EXCERPT = 200

      def initialize(thread:, listing:, viewer:, type:, view:, show_subject: false)
        @thread = thread
        @listing = listing
        @viewer = viewer
        @type = type
        @view = view
        @show_subject = show_subject
      end

      private

      attr_reader :thread, :listing, :viewer, :type, :view

      def first = thread.messages.first

      def author = listing.users[first.author_id]

      def excerpt = ::Notes::Mentions.display(first.body, listing.users).first.truncate(EXCERPT)

      def replies = thread.messages.size - 1

      def unread? = listing.unread?(thread, viewer)

      def show_subject? = @show_subject

      def subject_name = helpers.note_subject_name(listing.subject_of(thread), listing.container, type)

      # The row's last line: what it is on (a pinned or resolved row, which
      # stands outside its group), the replies, "new". Nothing when it has
      # none of them.
      def meta
        parts = []
        parts << tag.span(subject_name) if show_subject?
        parts << tag.span(t(".replies", count: replies), data: { note_replies: true }) if replies.positive?
        parts << tag.span(t(".new"), class: "text-accent", data: { note_new: true }) if unread?
        safe_join(parts, " · ")
      end

      def path
        helpers.admin_record_note_thread_path(*helpers.note_args(listing.container), thread,
          **{ view: (view unless view == "editor"), **helpers.admin_url_options }.compact)
      end
    end
  end
end
