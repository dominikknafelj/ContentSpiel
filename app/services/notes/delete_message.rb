module Notes
  # Deletes one message with its deliveries, its reactions and its files
  # (`Notes::Files.remove`: the rows in this transaction, the stored bytes
  # only once it has committed); the thread goes with its last message (notes spec
  # §3.5). Your own message needs the read right; someone else's needs the
  # container's edit right (`Authorization#moderation_refusal`).
  #
  # A message someone else deleted a moment ago is a success with nothing
  # recorded: the outcome the caller asked for is already there. A container
  # in the trash (or purged) is NOT that case: like a reply and an edit, the
  # delete answers "This note is gone" and writes nothing, so no notes write
  # runs without the container's lock (`Authorization#lock_container`).
  # `note.deleted` is recorded before the delete, in its transaction.
  #
  # Signals the record's stream (`Notes::Signals`), whether the thread stays
  # or goes with its last message; a message that was gone already signals
  # nobody. Each person whose inbox row goes with the message is told once
  # that their inbox got smaller (`Notes::Signals.inbox`, no ids) -- also
  # when the thread goes with it: a thread's last message holds every
  # delivery the thread has left.
  class DeleteMessage < ApplicationService
    include Authorization

    def initialize(message, actor: Current.actor)
      @message = message
      @actor = actor
    end

    def call
      # `&.`: a message loaded before its thread was removed has none
      # (`Authorization`, "A container that is nil").
      container = @message.thread&.container
      refused = read_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused

      unless own?(@message)
        refused = moderation_refusal(container) { |key| authorize!(key, container) }
        return denied(refused, container, message: I18n.t("admin.notes.errors.delete_others")) if refused
      end

      locked = true
      thread = Message.transaction(requires_new: true) do
        next locked = false unless lock_container(container)

        message = Message.where(id: @message.id).lock.first
        current = Thread.where(id: @message.thread_id).lock.first
        next current unless message && current

        record_event("note.deleted", subject: current.subject, snapshot: nil, metadata: note_metadata(current, message))
        Signals.threads(current)
        # Read before the destroy, whose cascade takes the rows: the people
        # whose inbox is about to lose a line.
        Delivery.where(message_id: message.id).distinct.pluck(:user_id).each { |user_id| Signals.inbox(user_id) }
        # Its files, before the destroy: the rows here, the bytes once this
        # has committed (`Notes::Files.remove`).
        Files.remove(Message.where(id: message.id))
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

      locked ? success(thread) : failure(nil, [ gone("note") ])
    end
  end
end
