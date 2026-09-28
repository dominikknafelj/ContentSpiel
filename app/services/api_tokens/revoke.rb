module ApiTokens
  # Revokes a single token (spec §7.2). Immediate -- once this returns, the
  # raw value that authenticated it no longer does. Called by the list's own
  # "Revoke" button, and by `Groups::Destroy` for a deleted group's tokens.
  class Revoke < ApplicationService
    # `group_deleted: true` is `Groups::Destroy` revoking every token of
    # the group it deletes (design spec §3.2).
    def initialize(token, actor: Current.actor, group_deleted: false)
      @token = token
      @actor = actor
      @group_deleted = group_deleted
    end

    # Anyone signed in may revoke their own tokens; anyone else's needs
    # `tokens.manage` (access-control design spec §3.3 "Tokens" -- the same
    # rule as `ApiTokens::Issue`). A token revoked because its group is
    # being deleted needs `groups.manage` instead: deleting a group revokes
    # its tokens by definition, whoever they belong to, so that's the
    # permission being exercised.
    def call
      if @group_deleted
        return denied("groups.manage", @token.group) unless authorize!("groups.manage", @token.group)
      elsif !(actor.is_a?(User) && actor.id == @token.user_id)
        return denied("tokens.manage", @token) unless authorize!("tokens.manage", @token)
      end

      metadata = @group_deleted ? { "reason" => "group deleted" } : {}
      ApiToken.transaction do
        @token.revoke!
        record_event("token.revoked", subject: @token, field_changes: Audit::Snapshot.field_changes_for(@token), metadata: metadata)
      end

      success(@token)
    end
  end
end
