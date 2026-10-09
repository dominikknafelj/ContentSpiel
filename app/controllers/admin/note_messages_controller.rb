module Admin
  # The messages of one thread: a reply, an edit of one's own, a delete. The
  # thread is one of the container's; a thread that is gone (its block
  # deleted, its last message deleted in another tab) answers the frame with
  # a sentence, never a 404 inside the drawer -- whether it was already gone
  # when the request arrived (`set_thread`) or went while the service ran
  # (`NoteContainer#answer_thread_failure`).
  class NoteMessagesController < BaseController
    include NoteContainer

    before_action :set_thread

    def create
      result = Notes::Reply.call(@thread, body: note_body)

      if result.ok?
        redirect_to thread_path(@thread), status: :see_other
      else
        answer_thread_failure(@thread, result, key: "thread-#{@thread.id}")
      end
    end

    def update
      message = @thread.messages.find_by(id: params[:id]) or return gone!
      result = Notes::EditMessage.call(message, body: note_body)

      if result.ok?
        redirect_to thread_path(@thread), status: :see_other
      else
        answer_thread_failure(@thread, result, key: "message-#{message.id}")
      end
    end

    def destroy
      message = @thread.messages.find_by(id: params[:id]) or return gone!
      result = Notes::DeleteMessage.call(message)

      if result.ok?
        # The thread, or the list when the thread went with its last message.
        redirect_to (result.record ? thread_path(@thread) : notes_path), status: :see_other
      else
        answer_thread_failure(@thread, result, key: "message-#{message.id}", body: "")
      end
    end

    private

    def set_thread
      @thread = container_threads.find_by(id: params[:thread_id]) or gone!
    end
  end
end
