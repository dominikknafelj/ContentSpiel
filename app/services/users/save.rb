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
  class Save < ApplicationService
    def initialize(user = User.new, attributes:, actor: Current.actor)
      @user = user
      @attributes = attributes.to_h.symbolize_keys
      @actor = actor
    end

    def call
      authorize!(@user.persisted? ? :update : :create, @user)

      attrs = @attributes.slice(:email_address, :password, :password_confirmation)
      attrs.except!(:password, :password_confirmation) if attrs[:password].blank?

      creating = !@user.persisted?
      @user.assign_attributes(attrs)
      return unconfirmed_password if attrs.key?(:password) && attrs[:password_confirmation].blank?
      return failure(@user) unless @user.save

      record_event(creating ? :user_created : :user_updated, user: @user)
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
