module ApiTokens
  # Revokes a single token (spec §7.2). Immediate -- once this returns, the
  # raw value that authenticated it no longer does. The list's own "Revoke"
  # button is the only caller today.
  class Revoke < ApplicationService
    def initialize(token, actor: Current.actor)
      @token = token
      @actor = actor
    end

    def call
      authorize!(:revoke, @token)

      @token.revoke!

      record_event(:api_token_revoked, token: @token)
      success(@token)
    end
  end
end
