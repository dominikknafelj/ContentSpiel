module ApiTokens
  # Mints the bearer token that authenticates MCP requests as `user` (spec
  # §7.2). This is the only place `ApiToken.generate!` is called from, so
  # there is exactly one place a plaintext token is ever produced, whatever
  # the caller -- the setup wizard's MCP-token step and CS Studio's own
  # "Create token" (`Admin::ApiTokensController#create`) both go through
  # here. Each call simply adds another active token alongside any existing
  # ones; CS Studio's own list is where an admin revokes one it's replacing
  # (`ApiTokens::Revoke`), not this service.
  class Issue < ApplicationService
    def initialize(user, actor: Current.actor)
      @user = user
      @actor = actor
    end

    def call
      authorize!(:issue, @user)

      token, raw = ApiToken.generate!(@user)

      record_event(:api_token_issued, token:)
      success([ token, raw ])
    end
  end
end
