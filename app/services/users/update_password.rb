module Users
  # Sets a user's password (access-control design spec §3.4, "direct writes
  # are removed"): the reset flow (`Admin::PasswordsController#update`)
  # today, and "Change my password" (Task 8) next.
  #
  # Who may (design spec §3.3 "Users"): any user may change their *own*
  # password; changing someone else's needs `users.manage`, and an owner's
  # is owner-only (`Users::OwnerProtection`). "Own" means a signed-in
  # `User` actor who is `user` -- never an API token, which acts for its
  # user only within its group's grants and has no business with the
  # password.
  #
  # The reset flow has no signed-in user at all (nil `Current.actor` on
  # `:admin`, which would be denied), so it passes `actor: user`: the
  # emailed reset token already authenticated this change as that user's
  # own, which is exactly the "own password" case above.
  #
  # `current_password:` is for "Change my password": when given it must
  # match, so a borrowed signed-in session can't take over the account
  # without knowing the password. The reset flow omits it.
  #
  # The password itself never reaches the log (Review Focus 5): the event
  # is `user.updated` with a `"credentials"` marker (`OwnerProtection#
  # user_field_changes`).
  class UpdatePassword < ApplicationService
    include OwnerProtection

    def initialize(user, password:, password_confirmation:, current_password: nil, actor: Current.actor)
      @user = user
      @password = password.to_s
      @password_confirmation = password_confirmation.to_s
      @current_password = current_password
      @actor = actor
    end

    def call
      unless own_password?
        return denied("users.manage", @user) unless authorize!("users.manage", @user)
        return owner_only_denial if owner_protected?
      end

      return current_password_mismatch if !@current_password.nil? && !@user.authenticate(@current_password)
      return blank_password if @password.blank?

      @user.assign_attributes(password: @password, password_confirmation: @password_confirmation)
      saved = User.transaction do
        @user.save || raise(ActiveRecord::Rollback)

        record_event("user.updated", subject: @user, field_changes: user_field_changes(@user))
        true
      end
      return failure(@user) unless saved

      success(@user)
    end

    private

    def own_password? = actor.is_a?(User) && actor == @user

    def current_password_mismatch
      @user.errors.add(:current_password, "is incorrect")
      failure(@user)
    end

    # `has_secure_password` silently ignores an empty password on an
    # existing user (it only validates presence on create), so a blank
    # submission would otherwise "succeed" without changing anything.
    def blank_password
      @user.errors.add(:password, :blank)
      failure(@user)
    end
  end
end
