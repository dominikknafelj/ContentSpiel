module Groups
  # Creates or updates a group (access-control design spec §3.2/§3.3
  # "Groups", §5 "Groups module"): name, description, members and grants.
  #
  #   Groups::Save.call(group, attributes: { name:, description:, member_ids:,
  #     grants: [{ permission:, scope: }] }, actor:)
  #
  # `member_ids` and `grants` are the group's *whole* new lists when given;
  # left out, they're left alone. Unknown user ids are ignored.
  #
  # Needs `groups.manage`. On top of that, no privilege escalation (Review
  # Focus 1) for anyone but an owner:
  #
  # - Every grant that is **new or changed** must be one the actor could
  #   hand out themselves (`AccessControl.can_grant?`: they hold the same
  #   key at the same or a wider scope). That covers "can't add a
  #   permission they lack", "can't widen a scope", and "can't widen a
  #   group they're a member of" in one rule: a change the actor's own
  #   grants already cover can't give them anything they don't have.
  # - **Unchanged** grants are not re-checked. A non-owner may rename a
  #   group whatever it holds -- and a stale
  #   grant (a deleted branch root, an unregistered content type, Review
  #   Focus 3) can never block a save, since "unchanged" is judged against
  #   the grants as they stand today (`AccessControl::LiveGrants`), stale
  #   values already taken out.
  # - Adding a **member** hands them every grant of the group, so each
  #   added member (the actor included -- "adding yourself to a group is a
  #   widening") needs every resulting grant to pass the same check.
  # - **Removing** a member or a grant (or narrowing a grant) needs the
  #   right to manage the group as it stands (`#removal_refusal`, final fix
  #   wave): every grant it holds must be one the actor could hand out.
  #
  # The editor submits the live values, plus -- carried, so an untouched save
  # changes nothing -- a content type that is no longer registered until the
  # editor presses Remove on it. A grant posted exactly as stored but for those
  # carried names is "unchanged" (`#live`); with anything else changed it is
  # judged raw, names included. A deleted page and a dead grant are still
  # dropped by the next save.
  class Save < ApplicationService
    def initialize(group = AccessControl::Group.new, attributes:, actor: Current.actor)
      @group = group
      @attributes = attributes.to_h.symbolize_keys
      @actor = actor
    end

    def call
      return denied("groups.manage", @group) unless authorize!("groups.manage", @group)

      stored = AccessControl::LiveGrants.new(@group.persisted? ? @group.grants.to_a : [])
      listed = twice_listed_permissions
      return listed_twice(listed) if listed.any?

      desired = @attributes.key?(:grants) ? normalize_grants(@attributes[:grants]) : nil
      old_member_ids = @group.persisted? ? @group.memberships.pluck(:user_id).sort : []
      new_member_ids = @attributes.key?(:member_ids) ? User.where(id: Array(@attributes[:member_ids]).compact_blank).pluck(:id).sort : old_member_ids

      # What the authorisation comparisons read; `desired` stays what is stored.
      compared = desired && live(desired, stored)

      refusal = removal_refusal(stored, compared, old_member_ids - new_member_ids)
      return refusal if refusal

      @group.assign_attributes(@attributes.slice(:name, :description))
      grants = (desired || []).map { |attrs| AccessControl::Grant.new(group: @group, **attrs) }
      return invalid(grants) unless @group.valid? & grants.all?(&:valid?)

      refusal = escalation_refusal(stored, compared, new_member_ids - old_member_ids)
      return refusal if refusal

      old_grants = grant_list(@group.persisted? ? @group.grants.to_a : [])

      saved = begin
        AccessControl::Group.transaction do
          @group.save || raise(ActiveRecord::Rollback)
          replace_grants(grants) if desired && desired != old_grants
          sync_members(old_member_ids, new_member_ids)
          record_changes(old_grants, desired, old_member_ids, new_member_ids)
          true
        end
      rescue ActiveRecord::RecordNotUnique
        # The unique index on (group, permission) caught what no check could:
        # another save of this group wrote a grant for one of these permissions
        # between our reading the group and replacing its grants. The whole
        # transaction is rolled back; the editor reloads and tries again.
        return failure(@group, [ "This group was changed elsewhere. Reload and try again." ])
      end
      return failure(@group) unless saved

      success(@group)
    end

    private

    # Permissions the posted grants list more than once, in the order first
    # repeated. A group holds one grant per permission (the unique index
    # `index_access_control_grants_on_group_id_and_permission`), so this is
    # malformed input, not a right the actor lacks: it is answered as a
    # validation failure BEFORE any authorisation comparison -- nothing is
    # written, and neither `group.updated` nor `access.denied` is recorded.
    # Judged on the list as posted, before `normalize_grants` collapses
    # identical entries, so "listed twice" means what it says. There is no
    # model validation on `Grant` for it: this service builds and validates the
    # new grants while the old rows still exist, so such a validation would
    # reject every re-save.
    def twice_listed_permissions
      return [] unless @attributes.key?(:grants)

      Array(@attributes[:grants]).map { |grant| grant.to_h.symbolize_keys[:permission].to_s }.tally.select { |_, count| count > 1 }.keys
    end

    def listed_twice(permissions)
      permissions.each do |key|
        label = AccessControl::Permissions.find(key)&.label || key
        @group.errors.add(:base, "#{label} is listed twice.")
      end
      failure(@group)
    end

    # `[{ permission:, scope: }]`, scopes normalized, in a stable order so
    # an unchanged list compares equal to the stored one.
    def normalize_grants(grants)
      Array(grants).map do |grant|
        grant = grant.to_h.symbolize_keys
        { permission: grant[:permission].to_s, scope: AccessControl::LiveGrants.normalize_scope(grant[:scope] || {}) }
      end.uniq.sort_by { |grant| [ grant[:permission], grant[:scope].to_json ] }
    end

    # The desired grants as the two authorisation comparisons below read them:
    # each one raw, exactly as posted and as it would be stored -- EXCEPT a grant
    # that is a stored live grant posted back with (some of) its own removed
    # content types still on it, which is read as that stored grant, unchanged.
    #
    # Why there is an exception at all. A content type that is no longer
    # registered matches nothing, so `LiveGrants` leaves it out of a stored
    # grant's scope; but the editor CARRIES it (a warn chip with Remove, a hidden
    # input; `LiveGrants::Entry#carried_attributes`) so that a form saved as
    # rendered changes nothing. Compared raw, every such untouched save would be
    # a changed grant -- a 403 for a non-owner who can't hand out that name, on
    # a group they only meant to rename.
    #
    # Why it is this narrow (fix round 2). A removed name is dormant, not
    # meaningless. While it is unregistered it grants nothing at all -- not even
    # on leftover posts that still carry that type (`Scoping::Condition`
    # intersects a grant's types with the registered ones) -- but the day a
    # plugin registers a type of that name again the grant matches it, with no
    # save in between. So a grant that carries one may only pass unchecked when
    # NOTHING ELSE about it changed. A posted grant is read as a stored one only
    # when all of this holds:
    #
    # - the stored grant is a live ENTRY (`LiveGrants#entries`) with removed types
    #   of its own. A dead grant -- one whose every type is gone -- is never
    #   rendered or submitted, so nothing of it is carried: reposting its name
    #   is a new grant;
    # - same permission;
    # - the posted scope, minus that entry's OWN removed types, is exactly the
    #   entry's live scope: the same live types, the same `own`, the same pages.
    #   (Scopes are normalised -- sorted, unique -- so order and repeats don't
    #   count; a name that only looks alike, "Retired" or " retired", is another
    #   name and stays in.) What the subtraction took out is therefore a subset
    #   of what that grant already holds as removed: the dormant right can only
    #   stay or shrink, never appear, move or widen;
    #
    # (A group holds one grant per permission and a request listing one twice
    # is refused up front, so each posted grant meets at most one stored entry
    # and a stored entry's removed names can't be dealt out over several.)
    #
    # Everything else is compared and checked raw, as before the editor carried
    # anything: `can_grant?` sees the removed name, and only an actor whose own
    # grant covers it (an unscoped holder; an owner is never asked) passes. Fix
    # round 1 stripped by permission and name alone, whatever else changed, and
    # so let a non-owner untick "Own only" on `{blog, retired, own}`, add a live
    # type beside the name, or move the name into another grant of the same
    # permission -- each checked as if the name weren't there, each stored with
    # it.
    #
    # The consequence, on purpose: a non-owner who couldn't hand out the removed
    # name can change such a grant only AFTER pressing Remove on it. Posting the
    # live scope without the name is the entry itself -- neither a removal nor
    # an escalation here, though stored and audited as the change it is (those
    # compare the raw lists). The editor's locked row (`Admin::
    # PermissionMatrixComponent`: a carried scope the viewer fails `can_grant?`
    # on is a greyed tick with no scope editor) is the UI's side of this rule;
    # this is the side a request meets, forged or not, however the row is drawn.
    #
    # Members. The added-member check in `#escalation_refusal` reads the same
    # list, so in a save that leaves such a grant untouched a new member is
    # judged against its LIVE scope -- what `can_manage_group?` and a
    # members-only save (no `grants:` at all) judge too, and what the editor
    # posted before it carried anything. Adding or removing a member of a group
    # that holds a removed type is therefore not blocked by the name; changing
    # the grant in the same save is.
    def live(grants, stored)
      grants.map do |grant|
        types = grant[:scope]["content_types"]
        next grant unless types

        entry = stored.entries.find do |candidate|
          candidate.permission == grant[:permission] && candidate.gone_types.intersect?(types) &&
            candidate.scope == grant[:scope].merge("content_types" => types - candidate.gone_types)
        end
        entry ? entry.attributes : grant
      end
    end

    def grant_list(grants)
      normalize_grants(grants.map { |grant| { permission: grant.permission, scope: grant.scope } })
    end

    # Validation failures (an unregistered key, a scope key the permission
    # doesn't take) come back on the group, like any other form error --
    # before the escalation check, which needs a registered key to ask about.
    def invalid(grants)
      grants.each do |grant|
        grant.errors.full_messages.each { |message| @group.errors.add(:base, "#{grant.permission}: #{message}") }
      end
      failure(@group)
    end

    # Taking something away -- a member, a grant (narrowing one is
    # removing the old version), or the whole group in `Groups::Destroy` --
    # needs the right to manage the group as it stands (final fix wave,
    # Important 2, `AccessControl.can_manage_group?`): otherwise
    # `groups.manage` alone would let a non-owner empty Admin, or strip
    # its grants, whatever they hold themselves. Judged on the stored
    # group, before anything is assigned. Stale values and dead grants
    # (`LiveGrants`) aren't counted as removals -- they match nothing, and
    # the editor drops them on every save.
    def removal_refusal(stored, desired, removed_member_ids)
      return if @group.new_record? || actor.nil? || AccessControl.owner?(actor)

      removed_grants = desired ? stored.attributes - desired : []
      return if removed_member_ids.empty? && removed_grants.empty?
      return if AccessControl.can_manage_group?(actor, @group)

      denied("groups.manage", @group)
    end

    # The first refusal, or nil. Owners and trusted code paths (nil actor,
    # already let through by `authorize!`) are never refused; a token --
    # even an owner's -- is judged on its effective rights (final fix wave,
    # Minor 1: `AccessControl.can_grant?` takes the token itself).
    def escalation_refusal(stored, desired, added_member_ids)
      return if actor.nil? || AccessControl.owner?(actor)

      unchanged = stored.attributes
      Array(desired).each do |grant|
        next if unchanged.include?(grant)
        return denied(grant[:permission], @group) unless AccessControl.can_grant?(actor, grant[:permission], grant[:scope])
      end

      return if added_member_ids.empty?

      (desired || unchanged).each do |grant|
        next if AccessControl.can_grant?(actor, grant[:permission], grant[:scope])

        label = AccessControl::Permissions.fetch(grant[:permission]).label.downcase
        return denied(grant[:permission], @group, message: "You can't add members to this group: you don't have permission to #{label}")
      end
      nil
    end

    # Replaced wholesale: a grant has no identity worth keeping beyond its
    # key and scope, and `destroy` (not `delete_all`) runs `Grant`'s
    # `after_commit`, which drops every actor's memoised grants.
    def replace_grants(grants)
      @group.grants.destroy_all
      grants.each(&:save!)
      @group.grants.reset
    end

    # Through `Membership` itself, not `group.user_ids =`: a has-many-
    # through assignment deletes join rows without callbacks, which would
    # skip `Membership`'s memo reset.
    def sync_members(old_ids, new_ids)
      AccessControl::Membership.where(group: @group, user_id: old_ids - new_ids).destroy_all
      (new_ids - old_ids).each { |user_id| AccessControl::Membership.create!(group: @group, user_id: user_id) }
      @group.users.reset
    end

    # `group.created`, or `group.updated` when anything changed. Grants and
    # members aren't columns, so they join the column changes as
    # `"grants" => [old list, new list]` and `"member_ids" => [old, new]`.
    def record_changes(old_grants, desired, old_member_ids, new_member_ids)
      if @group.previously_new_record?
        record_event("group.created", subject: @group, field_changes: Audit::Snapshot.field_changes_for(@group))
        return
      end

      changes = Audit::Snapshot.field_changes_for(@group)
      changes["grants"] = [ old_grants, desired ].as_json if desired && desired != old_grants
      changes["member_ids"] = [ old_member_ids, new_member_ids ] if old_member_ids != new_member_ids
      record_event("group.updated", subject: @group, field_changes: changes) if changes.any?
    end
  end
end
