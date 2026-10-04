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
    # `group:` is required: the caller chooses which group bounds the token
    # (design spec §3.3 "Tokens"). CS Studio's form offers only the groups
    # the user may assign (`AccessControl.permitted_groups_for`); the setup
    # wizard passes Admin for the first (owner) account.
    #
    # `name:` -- nil means "pick the next free Token N" (the setup wizard,
    # and a form that doesn't ask yet); any String is validated as given,
    # so a blank "" is a "Name can't be blank" failure rather than a quiet
    # default (round 3 decision D2).
    def initialize(user, group:, name: nil, actor: Current.actor)
      @user = user
      @group = group
      @name = name
      @actor = actor
    end

    # Who may (access-control design spec §3.3 "Tokens"): anyone signed in
    # may issue a token for *themselves* -- a signed-in `User` actor who is
    # `user`; an API token minting tokens isn't "themselves", and needs
    # `tokens.manage` like anyone issuing for someone else.
    #
    # Which group (Review Focus 1): one whose every grant the token's user
    # could hand out themselves (`AccessControl.can_assign_group?`) --
    # owners may choose any group. The token would be bounded by its
    # user's rights anyway (the intersection), but a token labelled
    # "Admin" that quietly can't do what Admin does is a lie in the list,
    # and a forged `group_id` is exactly the escalation attempt to refuse
    # out loud. Issuing for someone else, the actor must be able to assign
    # the group too (`#assignable_group?`). Trusted code paths (setup,
    # console) choose freely.
    #
    # The event carries the token's id, user and group (`Audit::Snapshot`),
    # never its digest or the raw value (Review Focus 5).
    def call
      unless own_token?
        return denied("tokens.manage", @user) unless authorize!("tokens.manage", @user)
      end
      return failure(ApiToken.new(user: @user), [ "Choose a group for the token" ]) if @group.nil?
      unless assignable_group?
        return denied("tokens.manage", @user, message: "You don't have permission to give a token the #{@group.name} group")
      end

      unless @name.nil?
        candidate = ApiToken.new(user: @user, group: @group, name: @name)
        return failure(candidate, candidate.errors.full_messages) unless candidate.valid?
      end

      token, raw = ApiToken.transaction do
        issued = ApiToken.generate!(@user, group: @group, name: @name)
        record_event("token.issued", subject: issued.first, metadata: { "group" => @group.name, "name" => issued.first.name })
        issued
      end

      success([ token, raw ])
    end

    private

    def own_token? = actor.is_a?(User) && actor == @user

    # The group must be within the token user's rights, and -- issuing for
    # someone else, or as a token (final fix wave, Minors 1 and 2) --
    # within the actor's own too: `tokens.manage` doesn't let anyone hand
    # out, through somebody else's token, a group they couldn't assign
    # themselves. A token actor is judged on its effective rights.
    def assignable_group?
      return true if AccessControl.trusted?(actor, Current.channel)

      AccessControl.can_assign_group?(@user, @group) && (own_token? || AccessControl.can_assign_group?(actor, @group))
    end
  end
end
