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

    def initialize(user, name:, actor: Current.actor)
      @user = user
      @name = name
      @actor = actor
    end

    def call
      unless actor.is_a?(User) && actor == @user
        # Always refused, even for a `users.manage` holder: that route is
        # `Users::Save`. The check is still made, so the denial and the
        # contract both go through the one authorization seam.
        authorize!("users.manage", @user)
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
