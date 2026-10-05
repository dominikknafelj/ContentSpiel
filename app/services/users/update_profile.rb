module Users
  # A signed-in user's own profile -- today only the name (design pass spec
  # §5.1). Not `Users::Save`: that one needs `users.manage` and is bounded by
  # what the actor could grant; this is "your own account", open to every
  # user the way `Users::UpdatePassword`'s own-password path is. Anyone
  # else's profile goes through `Users::Save`, so here it is simply refused
  # (and logged as a denial, like every refused write).
  #
  # Never an API token: a token acts for its user only within its group's
  # grants and has no business with the account itself, same as the password.
  class UpdateProfile < ApplicationService
    include OwnerProtection

    # authorize: none (the whole rule is "the actor is the user itself", checked in #call; AccessControl has no permission for it, and nobody else may, not even a users.manage holder)

    def initialize(user, name:, actor: Current.actor)
      @user = user
      @name = name
      @actor = actor
    end

    def call
      unless actor.is_a?(User) && actor == @user
        # Always refused, even for a `users.manage` holder: that route is
        # `Users::Save`. No `authorize!` here: its answer would be discarded,
        # and a call that cannot change the outcome only reads as a check.
        # The denial is logged against `users.manage`, the permission the
        # editor lacks for this route.
        return denied("users.manage", @user)
      end

      @user.name = @name
      saved = User.transaction do
        @user.save || raise(ActiveRecord::Rollback)
        record_event("user.updated", subject: @user, field_changes: user_field_changes(@user))
        true
      end
      saved ? success(@user) : failure(@user)
    end
  end
end
