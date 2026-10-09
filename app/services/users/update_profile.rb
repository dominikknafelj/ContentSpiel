module Users
  # A signed-in user's own profile: the name (design pass spec §5.1) and the
  # two notes settings, the mention chime and the desktop notification (notes
  # spec D18, D19, §6.4). They are one form with one footer on the account
  # screen (notes handoff, decision 13), so they are one save here: one
  # `authorize` rule, one transaction, one `user.updated` event that says
  # everything that changed -- a name that is refused takes the switches
  # down with it, and nothing is half saved. A setting that is not given
  # (`nil`) is left as it is; anything but `true` is off. Not `Users::Save`: that one needs `users.manage` and is bounded by
  # what the actor could grant; this is "your own account", open to every
  # user the way `Users::UpdatePassword`'s own-password path is. Anyone
  # else's profile goes through `Users::Save`, so here it is simply refused
  # (and logged as a denial, like every refused write). The notes settings
  # have no second route at all: `Users::Save` does not take them, because
  # nobody decides for another person whether their browser makes a sound or
  # puts a note's first line on their lock screen.
  #
  # Never an API token: a token acts for its user only within its group's
  # grants and has no business with the account itself, same as the password.
  class UpdateProfile < ApplicationService
    include OwnerProtection

    # authorize: none (the whole rule is "the actor is the user itself", checked in #call; AccessControl has no permission for it, and nobody else may, not even a users.manage holder)

    def initialize(user, name:, notes_sound: nil, notes_desktop: nil, actor: Current.actor)
      @user = user
      @name = name
      @notes_sound = notes_sound
      @notes_desktop = notes_desktop
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
      @user.notes_sound = (@notes_sound == true) unless @notes_sound.nil?
      @user.notes_desktop = (@notes_desktop == true) unless @notes_desktop.nil?
      saved = User.transaction do
        @user.save || raise(ActiveRecord::Rollback)
        record_event("user.updated", subject: @user, field_changes: user_field_changes(@user))
        true
      end
      saved ? success(@user) : failure(@user)
    end
  end
end
