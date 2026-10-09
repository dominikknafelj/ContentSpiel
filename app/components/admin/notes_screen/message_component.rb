module Admin
  module NotesScreen
    # One message: who, when, "edited", the text, and a "⋯" menu with Edit (the
    # author's) and Delete (the author's, and a moderator's: notes spec §3.4).
    # (Tasks 15 and 16 add the reactions and the files.)
    #
    # THE MENU ASKS THE SERVER. Edit and Delete are links to the thread again
    # with `?edit=<id>` or `?delete=<id>` (`asked`), and the answer draws this
    # one message with its edit form in place of the text, or with "Delete
    # this note?" under it. So a thread carries one edit form at most, never
    # one per message, nothing needs a script to be shown, and Cancel is the
    # thread without the parameter. The same form is drawn when its own save
    # was refused (`failed`), with the text that was typed.
    #
    # Its content, when it is given any, is drawn at the end of the line that
    # names the author: the thread hands its first message the "written on"
    # chip that way (handoff "Message": the chip sits on the first message
    # only), so this component needs to know neither the thread's origin nor
    # the tab being read.
    class MessageComponent < Admin::AdminComponent
      def initialize(message:, thread:, listing:, viewer:, type:, view:, failed: nil, asked: {})
        @message = message
        @thread = thread
        @listing = listing
        @viewer = viewer
        @type = type
        @view = view
        @failed = failed
        @asked = asked || {}
      end

      def dom_id = "note-message-#{message.id}"

      private

      attr_reader :message, :thread, :listing, :viewer, :type, :view, :failed, :asked

      def author = listing.users[message.author_id]

      def own? = viewer.present? && message.author_id == viewer.id

      def deletable? = own? || listing.moderator?(viewer)

      def key = "message-#{message.id}"

      def own_failure = (failed if failed && failed[:key] == key)

      # A save of this message that was refused with its text: only its
      # author has a form to see it in.
      def edit_failure = (own_failure if own? && own_failure && own_failure[:body].present?)

      # A refusal with no form to show it in: a delete, or an edit of someone
      # else's note (which only a forged request sends).
      def bare_failure = (own_failure if own_failure && !edit_failure)

      def editing? = own? && (edit_failure.present? || asked[:edit] == message.id)

      def confirming_delete? = deletable? && !editing? && asked[:delete] == message.id

      def args = helpers.note_args(listing.container)

      def frame_params = { view: (view unless view == "editor"), **helpers.admin_url_options }.compact

      def message_path = helpers.admin_record_note_message_path(*args, thread, message, **frame_params)

      def mentions_path = helpers.admin_record_note_mentions_path(*args)

      # The thread again, as the menu asks for it (`extra`) or as Cancel does.
      def thread_path(**extra) = helpers.admin_record_note_thread_path(*args, thread, **frame_params, **extra)

      # `turbo_prefetch: false`: the thread's GET marks it read
      # (`Admin::NoteThreadsController#mark_read`).
      def frame_link = { turbo_frame: "notes", turbo_prefetch: false }

      # The stored body as the field shows it -- names for tokens -- and the
      # map that turns them back; or what was typed, when the save failed.
      def editable
        edit_failure ? [ edit_failure[:body], edit_failure[:names] ] : ::Notes::Mentions.display(message.body, listing.users)
      end

      def cancel_class = "cursor-pointer rounded-cs text-[12px] text-dim underline underline-offset-[3px] hover:text-ink focus-visible:outline-2 focus-visible:outline-accent"
    end
  end
end
