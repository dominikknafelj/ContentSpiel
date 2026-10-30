module Users
  # Withdraws an invite (design answer M4, "Withdraw invite"): the invited
  # row is deleted, with its memberships, so the link finds nothing and the
  # accept page says "expired" (plan Ruling 3). Nothing else of the person
  # exists: an invited row has no sessions, tokens or content.
  #
  # Only an OPEN invite: a row that has accepted is an account, and deleting
  # one is `Users::Destroy`, with its owner rules and the tokens it revokes.
  # The row is locked and asked again, so a withdrawal that races an
  # acceptance deletes nobody.
  #
  # Needs `users.manage`, and a non-owner may not withdraw an invite into
  # groups that outrank them (`OwnerProtection#outranked?`). The event is
  # recorded before the delete, in its transaction, as `user.deleted` is: the
  # subject's label keeps the address once the row is gone.
  class WithdrawInvite < ApplicationService
    include OwnerProtection

    def initialize(user, actor: Current.actor)
      @user = user
      @actor = actor
    end

    def call
      return denied("users.manage", @user) unless authorize!("users.manage", @user)
      return owner_only_denial if owner_protected?
      return denied("users.manage", @user) if outranked?
      return not_invited unless @user.invited?

      group_ids = @user.memberships.pluck(:group_id)
      withdrawn = User.transaction do
        @user.lock!
        raise ActiveRecord::Rollback unless @user.invited?

        record_event("user.invite_withdrawn", subject: @user)
        @user.destroy || raise(ActiveRecord::Rollback)
        # A group's edit form lists its members (`Admin::StaleForm`).
        AccessControl::Group.where(id: group_ids).touch_all if group_ids.any?
        true
      end
      return not_invited unless withdrawn

      success(@user)
    end

    private

    def not_invited = failure(@user, [ ResendInvite::NOT_INVITED ])
  end
end
