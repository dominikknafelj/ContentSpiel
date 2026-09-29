module ApiTokens
  # Revokes a single token (spec §7.2). Immediate -- once this returns, the
  # raw value that authenticated it no longer does. Called by the list's own
  # "Revoke" button, and by `Groups::Destroy` for a deleted group's tokens.
  class Revoke < ApplicationService
    # `deleting_group:` is `Groups::Destroy` revoking every token of the
    # group it deletes (design spec §3.2) -- honoured only for a token of
    # *that* group (fix round 1, M2), so it can't be used to revoke an
    # arbitrary token on the strength of `groups.manage`.
    #
    # `deleting_user:` is `Users::Destroy` revoking the tokens of the user
    # it deletes (final fix wave, Minor 5) -- the same shape: honoured only
    # for a token of *that* user, and authorized by `users.manage` on them.
    def initialize(token, actor: Current.actor, deleting_group: nil, deleting_user: nil)
      @token = token
      @actor = actor
      @group_deleted = deleting_group.present? && deleting_group.persisted? && @token.group_id == deleting_group.id
      @deleting_group = deleting_group
      @user_deleted = deleting_user.present? && deleting_user.persisted? && @token.user_id == deleting_user.id
      @deleting_user = deleting_user
    end

    # Anyone signed in may revoke their own tokens; anyone else's needs
    # `tokens.manage` (access-control design spec §3.3 "Tokens" -- the same
    # rule as `ApiTokens::Issue`). A token revoked because its group is
    # being deleted needs `groups.manage` instead: deleting a group revokes
    # its tokens by definition, whoever they belong to, so that's the
    # permission being exercised. Likewise `users.manage` for the tokens of
    # a user being deleted.
    def call
      if @group_deleted
        return denied("groups.manage", @deleting_group) unless authorize!("groups.manage", @deleting_group)
      elsif @user_deleted
        return denied("users.manage", @deleting_user) unless authorize!("users.manage", @deleting_user)
      elsif !(actor.is_a?(User) && actor.id == @token.user_id)
        return denied("tokens.manage", @token) unless authorize!("tokens.manage", @token)
      end

      metadata =
        if @group_deleted then { "reason" => "group deleted" }
        elsif @user_deleted then { "reason" => "user deleted" }
        else {}
        end
      ApiToken.transaction do
        @token.revoke!
        record_event("token.revoked", subject: @token, field_changes: Audit::Snapshot.field_changes_for(@token), metadata: metadata)
      end

      success(@token)
    end
  end
end
