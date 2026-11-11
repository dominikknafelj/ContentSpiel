module Sessions
  # "Sign out everywhere else" and a row's End in Your account: a person ends
  # their own sessions but the one they act in (`keep`), or, with `only:`, one
  # session of theirs. Only their own: nobody ends another person's this way,
  # not even a holder of `users.manage` (an owner's route is `Sessions::EndAll`).
  #
  # `only:` is looked up among the user's own sessions. An id that is not one
  # of them (another user's, one already ended, one that never was) and the
  # kept session itself end nothing, record nothing and answer ok with 0, the
  # same answer as for a session of theirs that had already ended, so an id
  # tells the caller nothing about whose it is.
  #
  # One `session.ended` (`ended_by_self`, the count) per act, however many
  # rows, and none when nothing ended. The result's `record` is the count.
  class EndOthers < ApplicationService
    # authorize: none (the whole rule is "the actor is the user itself", checked in #call; AccessControl has no permission for it, and nobody else may, not even a users.manage holder)

    def initialize(user: Current.user, keep: Current.session, only: nil, actor: Current.actor)
      @user = user
      @keep = keep
      @only = only
      @actor = actor
    end

    def call
      # Never a token: it acts for its user within a group and has no business
      # with the account's sign-ins. The denial is logged against
      # `users.manage`, the permission anyone else would lack.
      return denied("users.manage", @user) unless actor.is_a?(User) && actor == @user

      sessions = @user.sessions
      sessions = sessions.where.not(id: @keep.id) if @keep
      sessions = sessions.where(id: @only) if @only
      return success(0) if @only && !sessions.exists?

      count = Session.transaction do
        ended = sessions.destroy_each_locked
        # No snapshot: the user did not change.
        record_event("session.ended", subject: @user, metadata: { "reason" => "ended_by_self", "count" => ended }, snapshot: nil) if ended.positive?
        ended
      end
      success(count)
    end
  end
end
