# Namespace for access control (design spec §3): a permission registry
# (`AccessControl::Permissions`) that built-ins and, later, plugins register
# against, plus -- from later tasks in this sub-project -- the groups and
# grants that assign those permissions to users and the checker that
# decides whether an actor may act (`AccessControl.allowed?`/`.scope`).
# The decision itself is `AccessControl.allowed?` below, delegating to
# `AccessControl::Checker`; an actor's grants are loaded once per request
# by `AccessControl::ActorGrants`.
module AccessControl
  # Raised by `Permissions.register` for a key that's already registered
  # (design spec §3.1) -- a developer error caught at boot, mirroring
  # `ContentModel::DuplicateType`/`RichText::DuplicateType`. The one
  # legitimate re-registration, a `to_prepare` reload, always calls
  # `Permissions.reset!` first (config/initializers/types.rb), so this only
  # fires for an actual duplicate, e.g. two plugins claiming the same key.
  class DuplicatePermission < StandardError; end

  # Raised by `Permissions.fetch` for a key that isn't registered, mirroring
  # `ContentModel::UnknownType`. `.find` is the non-raising counterpart, for
  # call sites (grant validation against a stale grant whose permission key
  # names a removed plugin's permission) that treat "unknown" as a fact of
  # life to route around rather than a bug to raise on.
  class UnknownPermission < KeyError; end

  class << self
    # Design spec §3.3 -- see `AccessControl::Checker` for the rules.
    # `key` is a registry key, a String or Symbol (`"posts.edit"`); an
    # unregistered one raises `UnknownPermission`. `record` is the `Post`,
    # `Page` or `ContentBlock` acted on (unsaved for a create). It's
    # required for a subject key (posts.*, pages.*) -- nil raises
    # ArgumentError, so a service can't get a scope-free allow by
    # forgetting its record -- and ignored for an admin-area key.
    def allowed?(actor, key, record = nil, channel: Current.channel)
      Checker.new(actor, key, record, channel).allowed?
    end

    # Does `actor` hold `key` anywhere, under any scope? For navigation
    # and buttons only (the sidebar's "Pages", a "New post" button before
    # a content type is chosen) -- never to authorize a write, which must
    # go through `allowed?` with the record. Owners, trusted code paths,
    # and the token intersection are decided exactly as in `allowed?`.
    #
    # "Under any scope" has one exception: a grant whose scope names content
    # types of which none is registered reaches no record at all, so it
    # doesn't count (`Scoping::Condition#dormant?`) -- its holder would
    # otherwise be shown a Posts entry leading to an empty list and buttons
    # that every service refuses. A deleted branch root is not looked up
    # here: that would cost a query on every page of CS Studio.
    def holds?(actor, key, channel: Current.channel)
      Checker.new(actor, key, nil, channel, anywhere: true).allowed?
    end

    def trusted?(actor, channel) = Checker.trusted?(actor, channel)

    # Design spec §3.3 "Scopes for reading" -- see `AccessControl::Scoping`.
    # `relation` (a `Post`, `Page` or `ContentBlock` relation) narrowed to
    # the records `allowed?(actor, key, record)` would allow: untouched for
    # owners and trusted code paths, `relation.none` when nothing can
    # match. `key` names a subject permission (a read key also admits its
    # subject's write grants); an admin-area key, or one for another
    # subject, raises ArgumentError. Costs no queries of its own beyond
    # loading the actor's grants, once per request.
    #
    # Trash (trash spec §5.1): only kept pages and posts, and only blocks
    # whose owner is kept, for everyone -- owners and trusted code paths
    # included. `trashed: true` flips a page or post relation to the
    # trashed rows instead, for the Trash screen alone; blocks have no
    # trash of their own, so asking for trashed blocks raises.
    def scope(actor, key, relation, channel: Current.channel, trashed: false)
      Scoping.new(actor, key, channel, trashed: trashed).apply(relation)
    end

    # The CS Studio page tree (design spec §3.3): the ids of the pages
    # `actor` may read, plus `context_only` -- the ancestors of those pages
    # that aren't readable themselves, which the tree shows greyed out,
    # without actions, so a readable page deep in the tree still has its
    # path to the root. (`context_only` is the spec's name, used the same
    # in `Admin::TreeNodeComponent`.) Three queries at most, whatever the
    # tree's size: the grants (memoised), the readable ids, and their
    # ancestors from the closure table (a subquery on the first, not a list
    # of ids).
    def tree_visibility(actor, channel: Current.channel)
      readable_pages = scope(actor, "pages.read", Page.all, channel: channel)
      readable = readable_pages.pluck(:id).to_set
      ancestors = PageHierarchy.where(descendant_id: readable_pages.select(:id)).distinct.pluck(:ancestor_id)
      { readable: readable, context_only: ancestors.to_set - readable }
    end

    # Design spec §3.3 "Performance": `allowed?` over a list of pages (the
    # tree's per-row buttons) would otherwise query the closure table once
    # per page for its branch. This loads every listed page's self-and-
    # ancestor ids in one query and keeps them on the page objects, where
    # `Checker.page_branch_ids` finds them. It's a snapshot, like any
    # preloaded association: a page moved elsewhere (another object, another
    # request) after the preload still answers from its old position until
    # it's loaded afresh -- `Page#reload` and a save of the object itself
    # drop the snapshot (`Page#forget_preloaded_branch`). Only call it on a
    # list about to be rendered; a write service is handed the record its
    # controller loaded for that request, never a preloaded list entry.
    # Returns `pages`.
    def preload_branches(pages)
      persisted = pages.select(&:persisted?)
      return pages if persisted.empty?

      found = PageHierarchy.where(descendant_id: persisted.map(&:id)).pluck(:descendant_id, :ancestor_id)
        .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
      persisted.each do |page|
        page.instance_variable_set(Checker::PRELOADED_BRANCH_IDS, found.fetch(page.id, []))
      end
      pages
    end

    def page_branch_ids(page) = Checker.page_branch_ids(page)

    # The pages among `pages` that `actor` may create a page UNDER: `pages.create`
    # is checked against the branch the new page would join, so each is asked as
    # `allowed?(actor, "pages.create", Page.new(parent: page))`, with every
    # page's branch preloaded in one query so the checks add none. The one
    # answer for every "which parent?" picker (the New page dialog's Inside, the
    # Trash screen's restore picker). It is deliberately NOT
    # `scope(actor, "pages.create", Page.all)`: that narrows to pages whose
    # *parent* is in a grant's branch, i.e. the would-be new pages, so a
    # branch-scoped user would never be offered the branch's own root.
    def creatable_parents(actor, pages, channel: Current.channel)
      preload_branches(pages.to_a).select { |page| allowed?(actor, "pages.create", Page.new(parent: page), channel: channel) }
    end

    # Is `actor` an owner? Only a `User` ever is: an API token -- even an
    # owner's -- acts within its group (the intersection, design spec §3.3
    # "Tokens"), so it's judged on those effective rights everywhere an
    # owner would be waved through (final fix wave, Minor 1).
    def owner?(actor) = actor.is_a?(User) && actor.owner?

    # No privilege escalation (design spec §3.3 "Groups"): may `actor` hand
    # out `key` with `scope` -- to a group they edit, or through a group
    # they pick for a token? Owners may grant anything. Anyone else needs a
    # grant of their own, for the *same key* (a held `posts.edit` doesn't
    # cover handing out `posts.read`, even though it implies it when
    # checking), that covers the requested scope. A held grant covers a
    # requested scope when every scope key the held grant has is also on
    # the requested one, and at least as narrow there:
    #
    # - `content_types`: the requested list is a subset of the held list;
    # - `page_ids`: every requested root is at or below one of the held
    #   roots (its closure-table ancestors, itself included, contain one);
    # - `own: true`: the requested grant is `own: true` too.
    #
    # A scope key the held grant lacks is no restriction, so anything is
    # covered on that dimension. A requested page id that no longer exists
    # has no ancestors, so it's never covered -- harmless to refuse, since
    # it would match nothing anyway.
    #
    # An `ApiToken` actor is judged on its effective rights (final fix
    # wave, Minor 1): the grant must be covered by its group *and* by its
    # user (an owner's token by its group alone) -- the same intersection
    # `allowed?` applies. A revoked or orphaned token covers nothing; so
    # does a nil actor (the trusted code paths are decided by callers,
    # before they ask this).
    #
    # Conservative: one held grant must cover the whole request on its
    # own. A union of grants doesn't count -- holding `{content_types:
    # ["blog"]}` and `{content_types: ["now_update"]}` doesn't let a user
    # hand out `{content_types: ["blog", "now_update"]}`, though together
    # they allow exactly that. Refusing a grant the user could split into
    # two is safe; merging scopes across grants (and across dimensions)
    # correctly isn't worth the risk here.
    def can_grant?(actor, key, scope = {})
      permission = Permissions.fetch(key)
      return true if owner?(actor)

      requested = scope.to_h.stringify_keys
      case actor
      when User then grants_cover?(ActorGrants.for(actor).user_grants, permission, requested)
      when ApiToken
        return false if actor.revoked_at.present? || actor.user.nil? || actor.group_id.nil?

        grants = ActorGrants.for(actor)
        grants_cover?(grants.token_grants, permission, requested) &&
          (actor.user.owner? || grants_cover?(grants.user_grants, permission, requested))
      else false
      end
    end

    # Design spec §3.3 "Tokens" and Review Focus 1: may `actor` hand `group`
    # on -- put a user into it, bind a token to it? Only if every grant of
    # the group is one they could hand out themselves (`can_grant?`), judged
    # on the grants AS STORED (`LiveGrants#as_stored`). `actor` is a `User`
    # or an `ApiToken` (see `can_grant?`); an owner may assign any group.
    #
    # "As stored" is the whole rule, so, per kind of stale value (see
    # `LiveGrants`, "TWO KINDS OF STALE"):
    #
    # - A content type that is no longer registered STAYS in the scope that
    #   is judged. The name grants nothing today (`Scoping::Condition`), but
    #   it is dormant, not gone: register a type of that name again and the
    #   grant matches it at once, for every member and every token of the
    #   group, with no save in between. Handing the group on hands that on.
    #   So `{content_types: ["blog", "retired"]}` takes an actor whose own
    #   grant covers both names (or names no types at all) -- holding "blog"
    #   is not enough -- and the same goes for a grant whose every type is
    #   removed (`{content_types: ["retired"]}`): dead today, a `LiveGrants`
    #   "dead" grant that the editor doesn't even show, and still a right the
    #   actor couldn't have granted. Judged with the names stripped, as "what
    #   the group reaches today", a `{blog}` holder could put a user or a
    #   token into such a group and so hand out, the day the type comes back,
    #   a right they never held.
    # - A deleted branch root is left out: page ids are never reused, so it
    #   can't come back, and a grant all of whose roots are deleted is
    #   skipped. Neither can widen anyone's rights, so neither may make a
    #   group unassignable (Review Focus 3: stale is never an error).
    # - A grant for a permission that is no longer registered is skipped:
    #   there is no registered key to ask `can_grant?` about.
    #
    # Costs what `LiveGrants.new` costs (one query, only when a grant names
    # pages) plus `can_grant?`'s closure-table query per pages grant: nothing
    # per content type, removed or not. Callers that ask for many groups
    # preload `grants` (`permitted_groups_for`, `Users::Manageability`).
    def can_assign_group?(actor, group)
      return true if owner?(actor)

      LiveGrants.new(group.grants.to_a).as_stored.all? do |grant|
        can_grant?(actor, grant[:permission], grant[:scope])
      end
    end

    # May `actor` manage `group` *as it stands* (final fix wave, Important
    # 2) -- take members out of it, remove or narrow its grants, delete it,
    # or change the group memberships of a user in it? Only if every grant
    # it holds is one they could hand out themselves: `can_assign_group?`,
    # so on the grants as stored, a removed content type's dormant name
    # included (see there). Otherwise `groups.manage` or `users.manage`
    # alone would let a non-owner strip Admin, or empty it, whatever they
    # hold. Trusted code paths (nil actor on a trusted channel) may; a nil
    # actor on any other channel may not.
    #
    # One rule for `Users::Save`, `Users::Manageability`, `Groups::Save`
    # and `Groups::Destroy`, and for what the group editor draws: a group
    # for which this is false is view-only. A group that still stores a
    # removed content type is therefore view-only for a manager who couldn't
    # grant that name, until someone who could -- an owner, a holder whose
    # own grant names no types or names that one -- presses Remove on it.
    def can_manage_group?(actor, group, channel: Current.channel)
      return trusted?(actor, channel) if actor.nil?

      can_assign_group?(actor, group)
    end

    # The groups `actor` may choose for a token (`can_assign_group?`), by
    # name.
    def permitted_groups_for(actor)
      groups = Group.includes(:grants).order(:name).to_a
      owner?(actor) ? groups : groups.select { |group| can_assign_group?(actor, group) }
    end

    private

    def grants_cover?(grant_set, permission, requested)
      held_grants = grant_set.for([ permission.key ])
      return false if held_grants.empty?

      requested_branches = branches_of(requested["page_ids"])
      held_grants.any? { |held| scope_covers?(held, requested, requested_branches) }
    end

    def scope_covers?(held, requested, requested_branches)
      held.scope.all? do |scope_key, held_value|
        case scope_key
        when "content_types"
          requested.key?("content_types") && (Array(requested["content_types"]) - Array(held_value)).empty?
        when "page_ids"
          held_roots = Array(held_value).map(&:to_i)
          requested.key?("page_ids") && requested_branches.values.all? { |branch| branch.intersect?(held_roots) }
        when "own"
          !held.scope_own? || ActiveModel::Type::Boolean.new.cast(requested["own"]) == true
        else false # a held key we don't understand covers nothing
        end
      end
    end

    # `{requested_root_id => [it and its ancestor ids]}` in one query on
    # the closure table. A root with no closure rows (a deleted page) gets
    # an empty branch, which no held root intersects.
    def branches_of(page_ids)
      ids = Array(page_ids).map(&:to_i)
      return {} if ids.empty?

      found = PageHierarchy.where(descendant_id: ids).pluck(:descendant_id, :ancestor_id)
        .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
      ids.index_with { |id| found.fetch(id, []) }
    end
  end
end
