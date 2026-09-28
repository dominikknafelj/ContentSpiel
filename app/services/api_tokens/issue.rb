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
    # `group:` defaults to the built-in Admin group, the same interim
    # default `ApiToken.generate!` itself falls back to (ruling R1, Task 2
    # brief) -- passed through explicitly rather than left for
    # `ApiToken.generate!` alone to supply, so a caller that already knows
    # which group it wants (CS Studio's "Create token" form) can pass one
    # without this service needing its own separate default logic. A later
    # task makes this required and checks the caller may actually assign
    # it (design spec §3.3: "a group only if every grant in it is also
    # allowed to them").
    def initialize(user, group: AccessControl::Group.find_by!(name: AccessControl::Seeds::ADMIN_NAME), actor: Current.actor)
      @user = user
      @group = group
      @actor = actor
    end

    # Who may (access-control design spec §3.3 "Tokens"): anyone signed in
    # may issue a token for *themselves* -- a signed-in `User` actor who is
    # `user`; an API token minting tokens isn't "themselves", and needs
    # `tokens.manage` like anyone issuing for someone else. Whether the
    # chosen group is one the user may hand out is Task 8's check
    # (`AccessControl.can_assign_group?`); until then the token is still
    # bounded by its user's own rights (the intersection).
    #
    # The event carries the token's id, user and group (`Audit::Snapshot`),
    # never its digest or the raw value (Review Focus 5).
    def call
      unless own_token?
        return denied("tokens.manage", @user) unless authorize!("tokens.manage", @user)
      end

      token, raw = ApiToken.transaction do
        issued = ApiToken.generate!(@user, group: @group)
        record_event("token.issued", subject: issued.first, metadata: { "group" => @group&.name })
        issued
      end

      success([ token, raw ])
    end

    private

    def own_token? = actor.is_a?(User) && actor == @user
  end
end
