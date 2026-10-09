module Notes
  # "Notify me" / "Stop notifying me" (decision D17): sets the actor's own
  # follow row either way. The spec calls this service `Notes::Follow`; that
  # constant is the record (`note_follows`), so the service has this name.
  # Needs the read right. A `false` row is an explicit unfollow, which
  # `Notes::Deliveries.follow` leaves alone until a new mention.
  class SetFollowing < ApplicationService
    include Authorization

    # audit: none (following a thread changes who is told, not the content or the thread; like a read mark it is the person's own setting)

    def initialize(thread, following:, actor: Current.actor)
      @thread = thread
      @following = following ? true : false
      @actor = actor
    end

    def call
      container = @thread.container
      refused = read_refusal(container) { |key| authorize!(key, container) }
      return denied(refused, container) if refused
      return success(@thread) unless actor_user

      outcome = with_locked_thread(@thread) do |thread|
        Follow.find_or_initialize_by(thread_id: thread.id, user_id: actor_user.id).update!(following: @following)
        thread
      end
      thread_answer(outcome, @thread)
    end
  end
end
