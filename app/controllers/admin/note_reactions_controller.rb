module Admin
  # A reaction on one message of one of the container's threads: the
  # viewer's own, given or taken back (`Notes::React`). The form says which
  # (`on`, read as a real boolean here: anything but a true value is "take it
  # back"), so the same request sent twice ends in the same place. The container was found through the
  # read scope first (`NoteContainer#set_container`), then the thread among
  # the container's, then the message among the thread's: a message id of
  # another thread or another record is "This note is gone", never a
  # reaction on that message.
  #
  # It answers the frame like every notes write: a 303 to the thread, which
  # draws the chips as they now are -- with `shown`, the message reacted to,
  # so a message folded into "Show N more" is not hidden again by the answer
  # to a press on it -- or the thread again with the reason under that
  # message (422, 403).
  class NoteReactionsController < BaseController
    include NoteContainer

    def create
      thread = container_threads.find_by(id: params[:thread_id]) or return gone!
      message = thread.messages.find_by(id: params[:id]) or return gone!
      result = Notes::React.call(message, emoji: params[:emoji], on: ActiveModel::Type::Boolean.new.cast(params[:on].to_s) == true)

      if result.ok?
        redirect_to thread_path(thread, shown: message.id), status: :see_other
      else
        answer_thread_failure(thread, result, key: "message-#{message.id}", body: "")
      end
    end
  end
end
