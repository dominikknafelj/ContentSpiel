module ApiTokens
  # Mints the bearer token that authenticates MCP requests as `user` (spec
  # §7.2). This is the only place `ApiToken.generate!` is called from --
  # the setup wizard's MCP-token step and Avo's "Regenerate my API token"
  # action both go through here now, so there is exactly one place a
  # plaintext token is ever produced, whatever the caller.
  #
  # `rotate:` is what "regenerate" means in practice: without it this just
  # adds another active token alongside any existing ones (fine for setup,
  # which mints the admin's first token), but Avo's action explicitly means
  # "replace," so it revokes the user's current active tokens first.
  class Issue < ApplicationService
    def initialize(user, rotate: false, actor: Current.actor)
      @user = user
      @rotate = rotate
      @actor = actor
    end

    def call
      authorize!(:issue, @user)

      token, raw = ApiToken.transaction do
        @user.api_tokens.active.each(&:revoke!) if @rotate
        ApiToken.generate!(@user)
      end

      record_event(:api_token_issued, token:)
      success([ token, raw ])
    end
  end
end
