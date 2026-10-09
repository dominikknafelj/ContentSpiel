module Notes
  # Changes the text of the actor's OWN message (notes spec §3.5): allowed
  # while they may still read the record, and to nobody else -- someone who
  # may edit the page can delete a note, never put words in its author's
  # mouth. There is no permission that grants it, so the refusal is logged
  # against the read key with its own sentence, as `Users::UpdateProfile`
  # logs its "only yourself" rule against `users.manage`.
  #
  # Only the people the edit NEWLY mentions are checked and told: someone
  # mentioned before who has since lost access stays in the text.
  class EditMessage < ApplicationService
    include Authorization

    def initialize(message, body:, actor: Current.actor)
      @message = message
      @body = body.to_s.strip
      @actor = actor
    end

    def call
      # `&.`: a message loaded before its thread was removed has none
      # (`Authorization`, "A container that is nil").
      thread = @message.thread
      container = thread&.container
      refused = read_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused
      return denied(Notes.read_key(container), container, message: I18n.t("admin.notes.errors.not_yours")) unless own?(@message)

      newly_mentioned = Mentions.ids(@body) - @message.mentioned_user_ids
      errors = body_errors(@body).presence || mention_errors(newly_mentioned, container)
      return failure(@message, errors) if errors.any?

      message = Message.transaction(requires_new: true) do
        current = lock_container(container) && Message.where(id: @message.id).lock.first
        next unless current
        next current if current.body == @body

        current.update!(body: @body, edited_at: Time.current)
        Deliveries.for_edit(current, newly_mentioned: newly_mentioned, actor_user: actor_user)
        record_event("note.edited", subject: thread.subject, snapshot: nil, metadata: note_metadata(thread, current))
        current
      end

      message ? success(message) : failure(@message, [ gone("note") ])
    end
  end
end
