module Notes
  # Pins a thread: a standing note, listed first (decision D1). Moderation:
  # the container's edit right. A pinned thread is always open, so a resolved
  # one can't be pinned: it is reopened first, which tells its followers.
  # Signals the record's stream (`Notes::Signals`) and no person: a pin is
  # addressed to nobody.
  class Pin < ApplicationService
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
        next thread if thread.pinned?
        next I18n.t("admin.notes.errors.pin_resolved") if thread.resolved?

        thread.update!(pinned: true, pinned_at: Time.current, pinned_by: actor_user)
        record_event("note.pinned", subject: thread.subject, snapshot: nil, metadata: note_metadata(thread))
        Signals.threads(thread)
        thread
      end
      thread_answer(outcome, @thread)
    end
  end
end
