module Invitations
  # What accepting an invitation does once the account is built, whichever
  # way it was proved: a typed password (`Invitations::Accept`) or the sign-in
  # provider (`Invitations::AcceptWithSso`). Included by both, so the two can
  # never make an account in different groups or record it differently.
  #
  # `accept_into(user)` locks the invitation's row and asks `used?` again
  # under the lock, so of two presses at once the second reads USED. It then
  # saves the account (the save validates again), puts it in the
  # invitation's groups, marks the invitation accepted and records
  # `invitation.accepted` as the new account, its actor and its subject at
  # once. A block given runs last, inside the same transaction and as the new
  # account, for what one way adds (the link's own event). It answers
  # `:accepted`, USED, or `:invalid` when the save refuses the account (the
  # account's `errors` then say why). A row withdrawn meanwhile raises
  # `ActiveRecord::RecordNotFound` from the lock, and an account made for the
  # address at the same moment `ActiveRecord::RecordNotUnique`: the caller
  # answers EXPIRED and USED for them.
  module Acceptance
    EXPIRED = :expired
    USED = :used

    private

    def accept_into(user)
      Invitation.transaction do
        @invitation.lock!
        next USED if @invitation.used?
        next :invalid unless user.save

        # From here on everything is recorded as the new account's.
        @user = @actor = user
        group_ids = @invitation.invitation_groups.pluck(:group_id).sort
        # Through `Membership` itself, as `Users::Save#sync_groups`, so its
        # `after_commit` drops the memoised grants.
        group_ids.each { |group_id| AccessControl::Membership.create!(user: @user, group_id: group_id) }
        @invitation.update!(accepted_at: Time.current, user: @user)

        changes = Audit::Snapshot.field_changes_for(@user)
        changes["group_ids"] = [ [], group_ids ] if group_ids.any?
        record_event("invitation.accepted", subject: @user, field_changes: changes, metadata: { "invitation_id" => @invitation.id })
        yield if block_given?
        :accepted
      end
    end
  end
end
