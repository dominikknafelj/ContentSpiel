module Users
  # Creates or updates a User (spec §6.1): email address, plus a password
  # only when one was actually typed.
  #
  # An edit screen's password/confirmation inputs are always present in the
  # submitted form (there's no other way to offer "change your password"
  # inline), blank whenever an editor isn't changing it -- `has_secure_
  # password`'s own confirmation validation runs the moment `password_
  # confirmation` is assigned at all, even to an empty string, which would
  # then fail to match a `password` this call never touched. So a blank
  # `password` here means "leave the password alone," and both fields are
  # dropped before assignment rather than passed through empty -- the same
  # "a blank value is a no-op, not a write" rule `Admin::FileParams` applies
  # to an untouched file input. A typed password, though, always needs its
  # confirmation (`#unconfirmed_password`).
  #
  # Permissions (access-control design spec §3.3 "Users"): `users.manage`,
  # plus the owner rule in `Users::OwnerProtection`.
  class Save < ApplicationService
    include OwnerProtection

    def initialize(user = User.new, attributes:, actor: Current.actor)
      @user = user
      @attributes = attributes.to_h.symbolize_keys
      @actor = actor
    end

    def call
      return denied("users.manage", @user) unless authorize!("users.manage", @user)
      return owner_only_denial if owner_protected?

      attrs = @attributes.slice(:email_address, :password, :password_confirmation)
      attrs.except!(:password, :password_confirmation) if attrs[:password].blank?

      @user.assign_attributes(attrs)
      return unconfirmed_password if attrs.key?(:password) && attrs[:password_confirmation].blank?

      saved = User.transaction do
        @user.save || raise(ActiveRecord::Rollback)

        created = @user.previously_new_record?
        changes = user_field_changes(@user)
        record_event(created ? "user.created" : "user.updated", subject: @user, field_changes: changes) if created || changes.any?
        true
      end
      return failure(@user) unless saved

      success(@user)
    end

    private

    # Final fix wave (C, P17): a typed password needs a typed confirmation.
    # `has_secure_password` only compares the two when the confirmation is
    # non-nil, so a password sent without one (a form missing the field, a
    # caller forgetting it) would otherwise be set unconfirmed. Validated
    # first so this error joins any others instead of replacing them.
    def unconfirmed_password
      @user.validate
      @user.errors.add(:password_confirmation, :blank)
      failure(@user)
    end
  end
end
