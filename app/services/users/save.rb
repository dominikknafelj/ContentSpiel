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
  # A password that did change ends that user's sessions, in the same
  # transaction (`OwnerProtection#end_sessions_after_password_change`): an
  # admin who resets a colleague's password after a leak signs out whoever
  # is using it. An admin changing their *own* password here stays signed
  # in on this session and loses the others, as on "Change my password".
  #
  # `name` is optional (design pass spec §5.1); it rides along with the
  # email as an ordinary attribute and reaches the event through
  # `user_field_changes` like any other column.
  #
  # Permissions (access-control design spec §3.3 "Users"): `users.manage`,
  # plus the owner rule in `Users::OwnerProtection`.
  #
  # Groups and the owner flag (Task 8), each only when its key is given:
  # - `group_ids` is the user's whole new list of groups. `users.manage`
  #   covers memberships, but adding someone to a group hands them its
  #   grants, so for a non-owner every *added* group must be one they could
  #   assign (`AccessControl.can_assign_group?` -- no privilege escalation,
  #   Review Focus 1), and every *removed* one a group they may manage as it
  #   stands (`AccessControl.can_manage_group?`, final fix wave).
  # - `owner` is owner-only (design spec §3.2); a value equal to the stored
  #   one, or an absent, nil or empty one, isn't a change. The only CS Studio
  #   request that passes it is `PATCH users/:id/owner`
  #   (`Admin::UsersController#owner`); the setup wizard passes `owner: true`
  #   for the founding owner it creates. Demoting the last owner is
  #   refused by `User`'s own validation. Recorded as `user.owner_changed`,
  #   apart from any other change's `user.updated`.
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
      return denied("users.manage", @user) if outranked?

      owner_change = owner_change?
      return denied("users.manage", @user, message: "Only an owner can change who is an owner") if owner_change && !actor_owner?

      old_group_ids = @user.persisted? ? @user.memberships.pluck(:group_id).sort : []
      new_group_ids = requested_group_ids || old_group_ids
      refusal = group_refusal(new_group_ids - old_group_ids, old_group_ids - new_group_ids)
      return refusal if refusal

      attrs = @attributes.slice(:email_address, :name, :password, :password_confirmation)
      attrs.except!(:password, :password_confirmation) if attrs[:password].blank?
      attrs[:owner] = !@user.owner if owner_change

      @user.assign_attributes(attrs)
      return unconfirmed_password if attrs.key?(:password) && attrs[:password_confirmation].blank?

      saved = User.transaction do
        @user.save || raise(ActiveRecord::Rollback)
        end_sessions_after_password_change
        sync_groups(old_group_ids, new_group_ids)
        touch_what_the_forms_show((old_group_ids - new_group_ids) | (new_group_ids - old_group_ids))
        record_changes(old_group_ids, new_group_ids)
        true
      end
      return failure(@user) unless saved

      success(@user)
    end

    private

    # Absent, nil and "" are no request about the flag (a blank form value, a
    # caller that never meant to name it): `Boolean` casts "" to nil, which differs
    # from either flag and would flip it. Not `blank?`, which is true for the real
    # value `false`, a demotion. Any other string is cast as Rails casts a
    # checkbox (anything but a "false"-like value is true), so the endpoint's
    # own `0`/`1` check is what keeps junk out.
    def owner_change?
      return false if @attributes[:owner].nil? || @attributes[:owner] == ""

      ActiveModel::Type::Boolean.new.cast(@attributes[:owner]) != @user.owner
    end

    # The existing groups among the submitted ids (unknown ids are
    # ignored), or nil when `group_ids` wasn't given.
    def requested_group_ids
      return unless @attributes.key?(:group_ids)

      AccessControl::Group.where(id: Array(@attributes[:group_ids]).compact_blank).pluck(:id).sort
    end

    # Adding someone to a group hands them its grants, so it must be a
    # group the actor could assign; taking someone out of one is managing
    # that group as it stands (final fix wave, Important 2) -- the same
    # test, `AccessControl.can_manage_group?`. For another user `outranked?`
    # has already required it of every group they're in; this also covers
    # the actor's own memberships. A token actor is judged on its
    # effective rights (Minor 1).
    def group_refusal(added_ids, removed_ids)
      return if (added_ids + removed_ids).empty? || actor_owner?

      groups = AccessControl::Group.includes(:grants).where(id: added_ids + removed_ids).order(:name)
      groups.each do |group|
        next if AccessControl.can_manage_group?(actor, group)

        verb = added_ids.include?(group.id) ? "add users to" : "remove users from"
        return denied("users.manage", @user, message: "You don't have permission to #{verb} the #{group.name} group")
      end
      nil
    end

    # Through `Membership` itself so its `after_commit` drops the memoised
    # grants (see `Groups::Save#sync_members`).
    def sync_groups(old_ids, new_ids)
      AccessControl::Membership.where(user: @user, group_id: old_ids - new_ids).destroy_all
      (new_ids - old_ids).each { |group_id| AccessControl::Membership.create!(user: @user, group_id: group_id) }
      @user.groups.reset
    end

    # `user.created`; otherwise `user.owner_changed` for the owner flag and
    # `user.updated` for everything else (group ids included), each only
    # when there's something to say.
    # The stale-save base of the user form (`Admin::StaleForm`) is this user's
    # `updated_at`, which a save moves only when a column of the user itself
    # changed, not for a membership. And the other side of a membership is a
    # group form (it lists the group's members): a group gained or lost here
    # makes an open edit of that group stale too. `touch_all` runs no callbacks.
    def touch_what_the_forms_show(changed_group_ids)
      return if changed_group_ids.empty?

      @user.touch unless @user.previously_new_record?
      AccessControl::Group.where(id: changed_group_ids).touch_all
    end

    def record_changes(old_group_ids, new_group_ids)
      changes = user_field_changes(@user)
      changes["group_ids"] = [ old_group_ids, new_group_ids ] if old_group_ids != new_group_ids

      if @user.previously_new_record?
        record_event("user.created", subject: @user, field_changes: changes)
        return
      end

      owner = changes.delete("owner")
      record_event("user.owner_changed", subject: @user, field_changes: { "owner" => owner }) if owner
      record_event("user.updated", subject: @user, field_changes: changes) if changes.any?
    end

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
