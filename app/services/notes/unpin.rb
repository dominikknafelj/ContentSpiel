module Notes
  # Takes a thread off the pinned list; it stays open. Moderation, like Pin.
  class Unpin < ApplicationService
    include Authorization

    def initialize(thread, actor: Current.actor)
      @thread = thread
      @actor = actor
    end

    def call
      container = @thread.container
      refused = moderation_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused

      outcome = with_locked_thread(@thread) do |thread|
        next thread unless thread.pinned?

        thread.update!(pinned: false, pinned_at: nil, pinned_by: nil)
        record_event("note.unpinned", subject: thread.subject, snapshot: nil, metadata: note_metadata(thread))
        thread
      end
      thread_answer(outcome, @thread)
    end
  end
end
