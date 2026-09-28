module AccessControl
  # The grants an actor acts under (design spec §3.3), loaded once per
  # request and memoised on `Current.access_grants` -- a Hash keyed by
  # actor -- so a page of 20 `allowed?` checks (a list, the sidebar, a row
  # of buttons) costs one query for a user, two for a token, not one per
  # check.
  #
  # - A `User` acts under `user_grants`: every grant of every group they
  #   belong to. `token_grants` is nil.
  # - An `ApiToken` acts under the intersection of `token_grants` (its one
  #   group's) and `user_grants` (its user's) -- the checker requires a
  #   match in both. The token's key includes its `group_id`, so a token
  #   whose group is changed mid-request never reads the old group's memo.
  #
  # Deliberately *not* memoised here: the owner flag and a token's
  # `revoked_at`. The checker reads those off the actor object on every
  # call, so they can't go stale behind a cached grant list.
  #
  # Staleness within a request: `Grant` and `Membership` clear the whole
  # memo after every commit (their `after_commit`), the same way
  # `SiteSetting` clears `Current.site`, so a group edit followed by a
  # check in the same request (or console session, where `Current` never
  # resets on its own) sees the new grants.
  class ActorGrants
    # One source's grants indexed by permission key, so a check only walks
    # the grants for the key (and its implied keys) it asks about.
    class GrantSet
      def initialize(grants)
        @by_key = grants.group_by(&:permission)
      end

      def for(keys) = keys.flat_map { |key| @by_key.fetch(key, []) }
    end

    attr_reader :user_grants, :token_grants

    def self.for(actor)
      memo = (Current.access_grants ||= {})
      case actor
      when User
        memo[[ "User", actor.id ]] ||= new(user_grants: load_user_grants(actor.id))
      when ApiToken
        memo[[ "ApiToken", actor.id, actor.group_id ]] ||=
          new(user_grants: load_user_grants(actor.user_id), token_grants: load_group_grants(actor.group_id))
      else
        raise ArgumentError, "#{actor.class} isn't an access-control actor"
      end
    end

    def self.reset! = Current.access_grants = nil

    # One query: the membership lookup is a subquery, not a second round
    # trip.
    def self.load_user_grants(user_id)
      GrantSet.new(Grant.where(group_id: Membership.where(user_id: user_id).select(:group_id)).to_a)
    end

    def self.load_group_grants(group_id) = GrantSet.new(Grant.where(group_id: group_id).to_a)

    def initialize(user_grants:, token_grants: nil)
      @user_grants = user_grants
      @token_grants = token_grants
    end
  end
end
