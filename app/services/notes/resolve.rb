module Notes
  # Resolves a thread (notes spec §3.5): kept, listed under "Resolved", not
  # counted. Needs the read right. Two people resolving at once is one
  # resolve: the second finds it done under the lock and succeeds without an
  # event or a second round of deliveries. A pinned thread is always open, so
  # resolving one unpins it in the same write. Signals the record's stream,
  # and every follower theirs (`Notes::Signals`); the no-op signals nobody.
  class Resolve < ApplicationService
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
        next thread if thread.resolved?

        thread.update!(state: "resolved", resolved_at: Time.current, resolved_by: actor_user, pinned: false, pinned_at: nil, pinned_by: nil)
        Deliveries.for_state(thread, "resolved", actor_user: actor_user)
        record_event("note.resolved", subject: thread.subject, snapshot: nil, metadata: note_metadata(thread))
        Signals.threads(thread)
        thread
      end
      thread_answer(outcome, @thread)
    end
  end
end
