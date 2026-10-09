module Admin
  module NotesScreen
    # One message: who, when, "edited", the text. (Task 6 adds Edit and
    # Delete; Tasks 15 and 16 the reactions and the files.)
    #
    # Its content, when it is given any, is drawn at the end of the line that
    # names the author: the thread hands its first message the "written on"
    # chip that way (handoff "Message": the chip sits on the first message
    # only), so this component needs to know neither the thread's origin nor
    # the tab being read.
    class MessageComponent < Admin::AdminComponent
      def initialize(message:, thread:, listing:, viewer:, type:, view:, failed: nil)
        @message = message
        @thread = thread
        @listing = listing
        @viewer = viewer
        @type = type
        @view = view
        @failed = failed
      end

      def dom_id = "note-message-#{message.id}"

      private

      attr_reader :message, :thread, :listing, :viewer, :type, :view, :failed

      def author = listing.users[message.author_id]

      def own? = viewer.present? && message.author_id == viewer.id
    end
  end
end
