module ApiTokens
  # Revokes a single token (spec §7.2). Immediate -- once this returns, the
  # raw value that authenticated it no longer does. The list's own "Revoke"
  # button is the only caller today.
  class Revoke < ApplicationService
    def initialize(token, actor: Current.actor)
      @token = token
      @actor = actor
    end

    # Anyone signed in may revoke their own tokens; anyone else's needs
    # `tokens.manage` (access-control design spec §3.3 "Tokens" -- the same
    # rule as `ApiTokens::Issue`).
    def call
      unless actor.is_a?(User) && actor.id == @token.user_id
        return denied("tokens.manage", @token) unless authorize!("tokens.manage", @token)
      end

      ApiToken.transaction do
        @token.revoke!
        record_event("token.revoked", subject: @token, field_changes: Audit::Snapshot.field_changes_for(@token))
      end

      success(@token)
    end
  end
end
