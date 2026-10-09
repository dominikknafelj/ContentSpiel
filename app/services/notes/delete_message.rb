module Notes
  # Deletes one message with its deliveries (and, once they exist, its
  # reactions and files); the thread goes with its last message (notes spec
  # §3.5). Your own message needs the read right; someone else's needs the
  # container's edit right (`Authorization#moderation_refusal`).
  #
  # A message someone else deleted a moment ago is a success with nothing
  # recorded: the outcome the caller asked for is already there.
  # `note.deleted` is recorded before the delete, in its transaction.
  class DeleteMessage < ApplicationService
    include Authorization

    def initialize(message, actor: Current.actor)
      @message = message
      @actor = actor
    end

    def call
      container = @message.thread.container
      refused = read_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused

      unless own?(@message)
        refused = moderation_refusal(container) { |key| authorize!(key, container) }
        return denied(refused, container, message: I18n.t("admin.notes.errors.delete_others")) if refused
      end

      thread = Message.transaction(requires_new: true) do
        lock_container(container)
        message = Message.where(id: @message.id).lock.first
        current = Thread.where(id: @message.thread_id).lock.first
        next current unless message && current

        record_event("note.deleted", subject: current.subject, snapshot: nil, metadata: note_metadata(current, message))
        message.destroy!
        newest = current.messages.reload.last
        if newest
          current.update!(last_message_at: newest.created_at)
          current
        else
          current.destroy!
          nil
        end
      end

      success(thread)
    end
  end
end
