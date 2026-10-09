module Users
  # A signed-in user's own notification settings for notes (notes spec D18,
  # D19, §6.4): the mention chime and the desktop notification. "Your own
  # account", like `Users::UpdateProfile`, and refused for anyone else the
  # same way -- nobody decides for another person whether their browser makes
  # a sound or puts a note's first line on their lock screen. Unlike the
  # name, there is no second route for a manager: `Users::Save` does not take
  # these two keys.
  #
  # Both settings are written by every call (the account screen's form always
  # sends both switches); anything but `true` is off.
  #
  # Never an API token: a token acts for its user within its group's grants
  # and has no business with the account itself.
  class UpdateNotifications < ApplicationService
    include OwnerProtection

    # authorize: none (the whole rule is "the actor is the user itself", checked in #call; AccessControl has no permission for it, and nobody else may, not even a users.manage holder)

    def initialize(user, sound:, desktop:, actor: Current.actor)
      @user = user
      @sound = sound == true
      @desktop = desktop == true
      @actor = actor
    end

    def call
      # Logged against `users.manage`, the permission a person changing
      # someone else's account would need, as `Users::UpdateProfile` does.
      return denied("users.manage", @user) unless actor.is_a?(User) && actor == @user

      @user.assign_attributes(notes_sound: @sound, notes_desktop: @desktop)
      saved = User.transaction do
        @user.save || raise(ActiveRecord::Rollback)
        record_event("user.updated", subject: @user, field_changes: user_field_changes(@user))
        true
      end
      saved ? success(@user) : failure(@user)
    end
  end
end
