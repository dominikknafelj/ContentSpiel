module AccessControl
  # One `AccessControl.allowed?` decision (design spec §3.3). Built per
  # call; the grants themselves come from the per-request
  # `ActorGrants` memo, so constructing one of these costs nothing.
  #
  # Order of business:
  # 1. Resolve the key -- an unknown key raises `UnknownPermission`, even
  #    for a trusted actor: it's a typo in code, not a denial to route
  #    around.
  # 2. A `ContentBlock` record is replaced by its owner (see
  #    `#resolve_block`), and the record is checked against the
  #    permission's subject.
  #    A subject key (posts.*, pages.*) needs a record: a nil one raises
  #    `ArgumentError` unless the caller asked `holds?` ("anywhere").
  # 3. Trusted code paths (nil actor on `:setup`/`:console`/`:system`/nil)
  #    are allowed; any other nil actor is denied.
  # 4. Owners are allowed; users need a matching grant; tokens need a
  #    matching grant in their group *and* their user must be allowed.
  class Checker
    # A nil channel counts as trusted too (a console or rake task where
    # nothing set one); any other value, a blank string included, doesn't.
    TRUSTED_CHANNELS = %i[setup console system].freeze

    # Design spec §3.3 "Implication": any of these on a subject also
    # satisfies that subject's `read`, within the same scope.
    WRITE_ACTIONS = %i[create edit publish move delete].freeze

    # Which permission-key prefix a block's owner maps to (design spec
    # §3.1 "Blocks").
    BLOCK_OWNER_PREFIX = { "Page" => "pages", "Post" => "posts" }.freeze

    # Where `AccessControl.preload_branches` leaves a page's branch ids.
    PRELOADED_BRANCH_IDS = :@access_control_branch_ids

    # The grant keys that can satisfy `permission` -- itself, plus, for a
    # subject's `read`, every registered write key on the same subject
    # (design spec §3.3 "Implication"). Shared with `Scoping`.
    def self.candidate_keys(permission)
      keys = [ permission.key ]
      if permission.action == :read && permission.subject
        prefix = permission.key.delete_suffix(".read")
        keys += WRITE_ACTIONS.map { |action| "#{prefix}.#{action}" }.select { |key| Permissions.find(key) }
      end
      keys
    end

    def self.trusted?(actor, channel)
      actor.nil? && (channel.nil? || TRUSTED_CHANNELS.include?(channel.to_sym))
    end

    # The page itself plus every ancestor id -- what a `page_ids` scope's
    # listed roots are matched against. An unsaved page has no closure
    # rows yet; it will sit under its parent, so it's in exactly the
    # branches its parent is in (and none, for a new root).
    #
    # A page passed through `AccessControl.preload_branches` answers from
    # that preload instead of querying (design spec §3.3 "Performance":
    # one closure query per page set, not one per row).
    def self.page_branch_ids(page)
      if page.instance_variable_defined?(PRELOADED_BRANCH_IDS)
        return page.instance_variable_get(PRELOADED_BRANCH_IDS)
      end
      return page.self_and_ancestor_ids unless page.new_record?

      page.parent ? page_branch_ids(page.parent) : []
    end

    # `anywhere: true` is `AccessControl.holds?`: "does the actor hold
    # this key under any scope at all?" -- no record, every grant for the
    # key counts whatever its scope, bar one that names only content types
    # that are no longer registered (`#grant_matches?`). Without it, a
    # subject key must come with the record it's about (see
    # `#check_subject!`).
    def initialize(actor, key, record, channel, anywhere: false)
      @actor = actor
      @permission = Permissions.fetch(key)
      @record = record
      @channel = channel
      @anywhere = anywhere
      resolve_block if @record.is_a?(ContentBlock)
      check_subject!
    end

    def allowed?
      return true if self.class.trusted?(@actor, @channel)

      case @actor
      when User then user_allowed?(@actor)
      when ApiToken then token_allowed?(@actor)
      else false # nil actor on :admin/:mcp, a Session, anything else
      end
    end

    private

    def user_allowed?(user)
      user.owner? || matches_any?(ActorGrants.for(user).user_grants, user.id)
    end

    # The intersection (design spec §3.3): the token's group must allow
    # the key *and* so must its user. `own` on either side means "the
    # token's user wrote it". An owner's token is limited by its group
    # only, since the owner half is always allowed.
    def token_allowed?(token)
      return false if token.revoked_at.present? || token.user.nil? || token.group_id.nil?

      grants = ActorGrants.for(token)
      matches_any?(grants.token_grants, token.user_id) &&
        (token.user.owner? || matches_any?(grants.user_grants, token.user_id))
    end

    # Grants combine with OR.
    def matches_any?(grant_set, user_id)
      grant_set.for(candidate_keys).any? { |grant| grant_matches?(grant, user_id) }
    end

    def candidate_keys = @candidate_keys ||= self.class.candidate_keys(@permission)

    # Every scope key present on the grant must match (AND); the rules
    # live in `Scoping::Condition`, shared with `AccessControl.scope` so a
    # list and a single check can never disagree. Fail-closed throughout
    # (Review Focus 3): a key this record can't be matched against, an
    # empty list, a stale page id or a content type that's no longer
    # registered all simply match nothing, never raise.
    #
    # `holds?` (`@anywhere`) has no record to match a scope against, so any
    # grant for the key counts -- except one that can't match any record
    # whatever it is: a scope naming content types of which none is
    # registered (`Scoping::Condition#dormant?`; no query). A nil record
    # otherwise only reaches here for an admin-area key, whose grants carry
    # no scope, so `matches?` on an empty scope is true without ever
    # touching the record.
    def grant_matches?(grant, user_id)
      condition = Scoping::Condition.new(grant, user_id, @permission)
      return !condition.dormant? if @anywhere
      return true if @record.nil?

      condition.matches?(@record, -> { branch_ids })
    end

    # `pages.create` is checked against the branch the new page will join
    # (design spec §3.3 "Create page"; "Move page" uses the same key for
    # the target), i.e. its parent's -- the caller passes the new page (or
    # the page being moved) with `parent` already set to the target. A
    # nil parent is creating the root: no branch, so only an unscoped
    # grant matches. Every other key is checked against the page's own
    # position in the stored tree.
    def branch_ids
      @branch_ids ||=
        if @permission.key == "pages.create"
          @record.parent ? self.class.page_branch_ids(@record.parent) : []
        else
          self.class.page_branch_ids(@record)
        end
    end

    # Design spec §3.1: blocks follow their owner's permissions. Only the
    # *action* of the passed key counts; its subject is replaced by the
    # owner's -- so `pages.edit` or `posts.edit` on a post-owned block both
    # check `posts.edit` on the post. Callers never need to branch on the
    # owner type, and the check is always against the right subject, so
    # there is no way to pass a key that grants a block through the wrong
    # owner. An action the owner's subject lacks (`pages.move` on a
    # post-owned block -> `posts.move`) raises `UnknownPermission`, since
    # it's a programmer error. So is a `create` key on a block: a block
    # is created by editing its owner (`pages.edit`/`posts.edit`), and
    # `pages.create` on a block would otherwise be matched against the
    # owning page's *parent* branch. Admin-area keys (no subject) leave
    # the block alone.
    def resolve_block
      return unless [ Page, Post ].include?(@permission.subject)
      if @permission.action == :create
        raise ArgumentError, "#{@permission.key} can't be checked on a block; blocks are created by editing their owner"
      end

      owner = @record.owner
      prefix = BLOCK_OWNER_PREFIX[owner.class.name] or
        raise ArgumentError, "a block owned by #{owner.class} has no permissions to follow"
      @permission = Permissions.fetch("#{prefix}.#{@permission.action}")
      @record = owner
    end

    # A record of the wrong class for the key (a `Page` for `posts.edit`)
    # is a programmer error: raise rather than deny, so it's caught in a
    # test instead of showing up as a mysterious refusal. Admin-area keys
    # (no subject) ignore whatever record a service passes along.
    #
    # A subject key with a nil record raises too (fix round 1, I1):
    # `ApplicationService#authorize!` hands its record straight through,
    # and a service that passed nil by mistake must not get a scope-free
    # allow. "Anywhere" is its own question, `AccessControl.holds?`.
    def check_subject!
      return if @permission.subject.nil? || @anywhere
      raise ArgumentError, "#{@permission.key} needs a record; use AccessControl.holds? for \"anywhere\"" if @record.nil?
      return if @record.is_a?(@permission.subject)

      raise ArgumentError, "#{@permission.key} applies to #{@permission.subject}, not #{@record.class}"
    end
  end
end
