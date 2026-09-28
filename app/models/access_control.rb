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
    def scope(actor, key, relation, channel: Current.channel)
      Scoping.new(actor, key, channel).apply(relation)
    end

    # The CS Studio page tree (design spec §3.3): the ids of the pages
    # `actor` may read, plus `context` -- the ancestors of those pages
    # that aren't readable themselves, which the tree shows greyed out,
    # without actions, so a readable page deep in the tree still has its
    # path to the root. Three queries at most, whatever the tree's size:
    # the grants (memoised), the readable ids, and their ancestors from
    # the closure table (a subquery on the first, not a list of ids).
    def tree_visibility(actor, channel: Current.channel)
      readable_pages = scope(actor, "pages.read", Page.all, channel: channel)
      readable = readable_pages.pluck(:id).to_set
      ancestors = PageHierarchy.where(descendant_id: readable_pages.select(:id)).distinct.pluck(:ancestor_id)
      { readable: readable, context: ancestors.to_set - readable }
    end

    # Design spec §3.3 "Performance": `allowed?` over a list of pages (the
    # tree's per-row buttons) would otherwise query the closure table once
    # per page for its branch. This loads every listed page's self-and-
    # ancestor ids in one query and keeps them on the page objects, where
    # `Checker.page_branch_ids` finds them. It's a snapshot, like any
    # preloaded association: a page moved after the preload still answers
    # from its old position until it's loaded afresh. Only call it on a
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

    # No privilege escalation (design spec §3.3 "Groups"): may `user` hand
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
    # Conservative: one held grant must cover the whole request on its
    # own. A union of grants doesn't count -- holding `{content_types:
    # ["blog"]}` and `{content_types: ["now_update"]}` doesn't let a user
    # hand out `{content_types: ["blog", "now_update"]}`, though together
    # they allow exactly that. Refusing a grant the user could split into
    # two is safe; merging scopes across grants (and across dimensions)
    # correctly isn't worth the risk here.
    def can_grant?(user, key, scope = {})
      permission = Permissions.fetch(key)
      return true if user.owner?

      requested = scope.to_h.stringify_keys
      held_grants = ActorGrants.for(user).user_grants.for([ permission.key ])
      return false if held_grants.empty?

      requested_branches = branches_of(requested["page_ids"])
      held_grants.any? { |held| scope_covers?(held, requested, requested_branches) }
    end

    # Design spec §3.3 "Tokens" and Review Focus 1: a token's group must be
    # one whose every grant the user could hand out themselves. A grant
    # whose permission is no longer registered is skipped -- it matches
    # nothing, so it can't widen anyone's rights (Review Focus 3).
    def can_assign_group?(user, group)
      return true if user.owner?

      group.grants.all? do |grant|
        grant.permission_definition.nil? || can_grant?(user, grant.permission, grant.scope)
      end
    end

    # The groups `user` may choose for a token (`can_assign_group?`), by
    # name.
    def permitted_groups_for(user)
      groups = Group.includes(:grants).order(:name).to_a
      user.owner? ? groups : groups.select { |group| can_assign_group?(user, group) }
    end

    private

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
