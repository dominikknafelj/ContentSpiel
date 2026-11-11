module Admin
  module NotesScreen
    # The page's one copy of the counts (`#notes-counts`), read again and drawn
    # by a block delete's answer through the stream slot `editor.block.removed`:
    # the notes on what was deleted are gone with it (`Notes::Remove`), and
    # `admin--notes--drawer` fills the header's number, every marker and the
    # next delete dialog's warning from this copy as it lands.
    class CountsStreamComponent < Admin::AdminComponent
      def initialize(record:, viewer:, data: nil, **)
        @record = record
        @viewer = viewer
      end

      def stream_target = "notes-counts"

      def call
        render(CountsComponent.new(counts: ::Notes::Counts.for_container(@record, user: ::Notes.user_of(@viewer)), id: stream_target))
      end
    end
  end
end
