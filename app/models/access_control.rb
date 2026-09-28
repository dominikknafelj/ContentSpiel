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
    # `Page` or `ContentBlock` acted on (unsaved for a create), or nil for
    # "anywhere"/an admin-area key.
    def allowed?(actor, key, record = nil, channel: Current.channel)
      Checker.new(actor, key, record, channel).allowed?
    end

    def trusted?(actor, channel) = Checker.trusted?(actor, channel)

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
