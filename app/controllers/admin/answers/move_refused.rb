module Admin
  module Answers
    # A move the Move to… dialog sent (images or a folder) that was refused:
    # the dialog's list drawn again in its frame, the refusal on top as a
    # danger notice (`choices`, an `Admin::MediaLibrary::MoveChoicesComponent`
    # with its `refusal:`), from the tree as it now is, so a folder deleted
    # meanwhile is no longer offered. The dialog stays open and
    # `admin--media--move` puts the focus on the notice. A move sent another
    # way is refused with a toast (`ImagesMoved#refused`, `FolderRefused#toast`).
    class MoveRefused
      FRAME_ID = Admin::MediaLibrary::MoveDialogComponent::FRAME_ID

      def initialize(view:)
        @turbo_stream = Answers.stream_builder(view)
      end

      def answer(choices:, status:)
        Answer.new(status: status, streams: [ @turbo_stream.update(FRAME_ID, choices) ])
      end
    end
  end
end
