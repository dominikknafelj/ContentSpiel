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
  # editor presses Remove on it (`#live`). A deleted page and a dead grant
  # are still dropped by the next save.
  class Save < ApplicationService
    def initialize(group = AccessControl::Group.new, attributes:, actor: Current.actor)
      @group = group
      @attributes = attributes.to_h.symbolize_keys
      @actor = actor
    end

    def call
      return denied("groups.manage", @group) unless authorize!("groups.manage", @group)

      stored = AccessControl::LiveGrants.new(@group.persisted? ? @group.grants.to_a : [])
      desired = @attributes.key?(:grants) ? normalize_grants(@attributes[:grants]) : nil
      old_member_ids = @group.persisted? ? @group.memberships.pluck(:user_id).sort : []
      new_member_ids = @attributes.key?(:member_ids) ? User.where(id: Array(@attributes[:member_ids]).compact_blank).pluck(:id).sort : old_member_ids

      refusal = removal_refusal(stored, desired, old_member_ids - new_member_ids)
      return refusal if refusal

      @group.assign_attributes(@attributes.slice(:name, :description))
      grants = (desired || []).map { |attrs| AccessControl::Grant.new(group: @group, **attrs) }
      return invalid(grants) unless @group.valid? & grants.all?(&:valid?)

      refusal = escalation_refusal(stored, desired, new_member_ids - old_member_ids)
      return refusal if refusal

      old_grants = grant_list(@group.persisted? ? @group.grants.to_a : [])

      saved = AccessControl::Group.transaction do
        @group.save || raise(ActiveRecord::Rollback)
        replace_grants(grants) if desired && desired != old_grants
        sync_members(old_member_ids, new_member_ids)
        record_changes(old_grants, desired, old_member_ids, new_member_ids)
        true
      end
      return failure(@group) unless saved

      success(@group)
    end

    private

    # `[{ permission:, scope: }]`, scopes normalized, in a stable order so
    # an unchanged list compares equal to the stored one.
    def normalize_grants(grants)
      Array(grants).map do |grant|
        grant = grant.to_h.symbolize_keys
        { permission: grant[:permission].to_s, scope: AccessControl::LiveGrants.normalize_scope(grant[:scope] || {}) }
      end.uniq.sort_by { |grant| [ grant[:permission], grant[:scope].to_json ] }
    end

    # The desired grants with the content types the EDITOR CARRIES left out:
    # a type that is no longer registered and that the STORED grant of the same
    # permission already holds. That is a dead scope value the group has today,
    # not part of what the grant means, and the editor submits it (a chip with
    # Remove, a hidden input) so that a form saved as rendered changes nothing.
    # Compared raw, every untouched save would look like a changed grant.
    #
    # Nothing else is left out. Any other unregistered name -- one the stored
    # grant doesn't hold -- stays in the compared scope and goes through
    # `can_grant?` / `can_manage_group?` like any value: it is dormant only until
    # a plugin registers a type of that name, and then it would grant on it.
    # Only the *comparisons* use this; what is stored, and what the audit event
    # lists, is the raw list, so pressing Remove (the value gone from the
    # submission) is a real change.
    def stored_grants = @stored_grants ||= (@group.persisted? ? @group.grants.to_a : [])

    def live(grants, stored_grants)
      registered = AccessControl::Permissions.content_type_choices
      carried = stored_grants.group_by(&:permission).transform_values do |held|
        held.flat_map(&:scope_content_types).uniq - registered
      end
      grants.map do |grant|
        types = grant[:scope]["content_types"]
        gone = carried.fetch(grant[:permission], [])
        next grant if types.nil? || gone.empty?

        { permission: grant[:permission], scope: grant[:scope].merge("content_types" => types - gone) }
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

      removed_grants = desired ? stored.attributes - live(desired, stored_grants) : []
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
      desired = live(desired, stored_grants) if desired
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
