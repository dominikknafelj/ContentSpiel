module Users
  # Rules every user-changing service shares (access-control design spec
  # §3.3 "Users"):
  #
  # - Owner accounts are owner-only. `users.manage` covers other users, but
  #   not an owner's: a non-owner who could change an owner's email or
  #   password could simply sign in as them, which would make the owner
  #   flag -- the one privilege no group can grant -- worth no more than
  #   `users.manage`. So only an owner may edit, reset or delete an owner
  #   (Review Focus 1, no privilege escalation).
  # - A non-owner manages another user only if that user's rights are a
  #   subset of their own (`#outranked?`, fix round 1).
  # - A password change never reaches the log: `password_digest` is
  #   scrubbed from every snapshot and changes hash (Review Focus 5), so
  #   `user_field_changes` records that it changed as `"credentials"`
  #   instead -- a key no `filter_parameters` entry matches, with no value
  #   derived from the password.
  module OwnerProtection
    private

    def owner_protected? = @user.persisted? && @user.owner? && !actor_owner?

    def actor_owner? = actor_user.nil? ? AccessControl.trusted?(actor, Current.channel) : actor_user.owner?

    # Fix round 1 (I1), the same idea one level down: a non-owner may only
    # manage users whose rights are a subset of their own -- every group
    # the target belongs to must be one the actor could assign
    # (`AccessControl.can_assign_group?`). Otherwise `users.manage` alone
    # would let them reset an Admin member's password or email, sign in as
    # them, and hold every right Admin has. Owners (and trusted code
    # paths) are unaffected; acting on yourself is never "outranked".
    def outranked?
      return false if @user.new_record? || actor_owner? || actor_user.nil? || @user == actor_user

      AccessControl::Group.includes(:grants).where(id: @user.memberships.select(:group_id)).any? do |group|
        !AccessControl.can_assign_group?(actor_user, group)
      end
    end

    def owner_only_denial
      denied("users.manage", @user, message: "You don't have permission to change an owner's account")
    end

    def user_field_changes(user)
      changes = Audit::Snapshot.field_changes_for(user)
      changes["credentials"] = [ nil, "password changed" ] if user.saved_change_to_password_digest? && !user.previously_new_record?
      changes
    end
  end
end
