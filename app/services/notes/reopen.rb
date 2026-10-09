module Notes
  # Reopens a resolved thread (notes spec §3.5). Needs the read right; a
  # thread that is open already is a success with nothing recorded.
  class Reopen < ApplicationService
    include Authorization

    def initialize(thread, actor: Current.actor)
      @thread = thread
      @actor = actor
    end

    def call
      container = @thread.container
      refused = read_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused

      outcome = with_locked_thread(@thread) do |thread|
        next thread if thread.open?

        thread.update!(state: "open", resolved_at: nil, resolved_by: nil)
        Deliveries.for_state(thread, "reopened", actor_user: actor_user)
        record_event("note.reopened", subject: thread.subject, snapshot: nil, metadata: note_metadata(thread))
        thread
      end
      thread_answer(outcome, @thread)
    end
  end
end
