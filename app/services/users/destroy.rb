module Users
  # Permanently deletes a User (spec §6.1/§6.2). "The last user can't be
  # deleted" lives on the model itself (`User#ensure_not_last_owner`, a
  # `before_destroy`), so it holds regardless of which door a delete comes
  # through; this service exists so every caller (CS Studio, and MCP/console
  # later) answers through the same `Result` shape every other write does,
  # rather than each checking `user.destroy`'s boolean return by hand.
  #
  # Deleting *yourself* is allowed, as long as you're not the last user --
  # this service has no opinion on sessions at all; ending the caller's own
  # session and redirecting to sign-in is `Admin::UsersController#destroy`'s
  # job, since only the controller knows which request this is.
  #
  # Needs `users.manage`, and deleting an owner is owner-only
  # (`Users::OwnerProtection`). `user.deleted` is recorded before the
  # destroy, in its transaction, so a refused one (the last owner) rolls
  # the event back with it.
  class Destroy < ApplicationService
    include OwnerProtection

    def initialize(user, actor: Current.actor)
      @user = user
      @actor = actor
    end

    def call
      return denied("users.manage", @user) unless authorize!("users.manage", @user)
      return owner_only_denial if owner_protected?

      destroyed = User.transaction do
        record_event("user.deleted", subject: @user)
        @user.destroy || raise(ActiveRecord::Rollback)
      end

      return failure(@user) unless destroyed

      success(@user)
    end
  end
end
