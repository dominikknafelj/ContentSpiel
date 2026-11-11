module Sessions
  # The user editor's "End all sessions": an owner ends every session of
  # another user. Owner-only, like the other owner zone actions: an account
  # that someone else may be signed in to is the owner's call. Refused on the
  # owner's own account (ruling R4): that is Your account's "Sign out
  # everywhere else" (`Sessions::EndOthers`), which keeps the session the
  # owner acts in, where this would end it under them.
  #
  # One `session.ended` (`ended_by_owner`, the count) per act, however many
  # rows, and none when nothing was open. The result's `record` is the count.
  class EndAll < ApplicationService
    # authorize: none (owner-only, asked through Users::Manageability.actor_owner? in #call as the other owner-only actions ask it; no AccessControl permission says "owner")

    def initialize(user, actor: Current.actor)
      @user = user
      @actor = actor
    end

    def call
      return denied("users.manage", @user) unless Users::Manageability.actor_owner?(actor)
      return failure(@user, [ I18n.t("admin.components.users_screen.sessions_zone.reason_own") ]) if @user == actor

      count = Session.transaction do
        ended = @user.sessions.destroy_each_locked
        # No snapshot: the user did not change.
        record_event("session.ended", subject: @user, metadata: { "reason" => "ended_by_owner", "count" => ended }, snapshot: nil) if ended.positive?
        ended
      end
      success(count)
    end
  end
end
