module Users
  # Sets a user's password (access-control design spec §3.4, "direct writes
  # are removed"): the reset flow (`Admin::PasswordsController#update`)
  # and "Change my password" (`Admin::AccountsController`).
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
  # A change ends the user's sessions, in the same transaction
  # (`OwnerProtection#end_sessions_after_password_change`): all of them,
  # except -- for a signed-in user changing their own password -- the
  # session they are doing it in. The reset flow passes
  # `keep_acting_session: false`: its `actor:` is the user too, but the
  # emailed token made the change, not a session, so a session that happens
  # to be signed in in the same browser goes with the rest.
  #
  # The password itself never reaches the log (Review Focus 5): the event
  # is `user.updated` with a `"credentials"` marker (`OwnerProtection#
  # user_field_changes`).
  class UpdatePassword < ApplicationService
    include OwnerProtection

    def initialize(user, password:, password_confirmation:, current_password: nil, keep_acting_session: true, actor: Current.actor)
      @user = user
      @password = password.to_s
      @password_confirmation = password_confirmation.to_s
      @current_password = current_password
      @keep_acting_session = keep_acting_session
      @actor = actor
    end

    def call
      unless own_password?
        return denied("users.manage", @user) unless authorize!("users.manage", @user)
        return owner_only_denial if owner_protected?
        return denied("users.manage", @user) if outranked?
      end

      return current_password_mismatch if !@current_password.nil? && !@user.authenticate(@current_password)
      return blank_password if @password.blank?

      @user.assign_attributes(password: @password, password_confirmation: @password_confirmation)
      saved = User.transaction do
        @user.save || raise(ActiveRecord::Rollback)
        end_sessions_after_password_change(keep_acting_session: @keep_acting_session)

        record_event("user.updated", subject: @user, field_changes: user_field_changes(@user))
        true
      end
      return failure(@user) unless saved

      success(@user)
    end

    private

    def own_password? = actor.is_a?(User) && actor == @user

    # A whole sentence for the field and for the summary alike
    # (config/locales/en.yml drops the attribute prefix for it). Wording
    # only: whether this refuses, and what it leaves untouched, is unchanged.
    def current_password_mismatch
      @user.errors.add(:current_password, "That's not your current password.")
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
