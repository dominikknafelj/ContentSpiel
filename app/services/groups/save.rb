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
  #   group whatever it holds -- and a value that is gone for good (a
  #   deleted branch root, Review Focus 3) can never block a save, since
  #   "unchanged" is judged against the grants as they stand today
  #   (`AccessControl::LiveGrants`), such values already taken out. A
  #   removed content type's name is not gone for good, and is carried.
  # - Adding a **member** hands them every grant of the group, so each
  #   added member (the actor included -- "adding yourself to a group is a
  #   widening") needs every grant the group will hold after this save to
  #   pass the same check -- AS STORED, a removed content type's name
  #   included, changed in this save or not (`#escalation_refusal`).
  # - **Removing** a member or a grant (or narrowing a grant) needs the
  #   right to manage the group as it stands (`#removal_refusal`, final fix
  #   wave): every grant it holds must be one the actor could hand out,
  #   again as stored (`AccessControl.can_manage_group?`). Giving up a
  #   removed content type's name is a removal like any other, whether the
  #   name sits beside a live type or is all a (dead) grant has left.
  #
  # The editor submits the live values, plus -- carried, so an untouched save
  # changes nothing -- a content type that is no longer registered until the
  # editor presses Remove on it. A grant posted exactly as stored but for those
  # carried names is "unchanged" (`#live`); with anything else changed it is
  # judged raw, names included. A deleted page and a dead grant are still
  # dropped by the next save of the form -- which, for a dead grant whose
  # content types could be registered again, is a removal and takes someone
  # who may manage the group. Membership is the one thing an unchanged grant
  # is still judged for: a member added, or taken out, meets the grants as
  # stored, carried names included.
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

      refusal = removal_refusal(stored, desired, old_member_ids - new_member_ids)
      return refusal if refusal

      @group.assign_attributes(@attributes.slice(:name, :description))
      grants = (desired || []).map { |attrs| AccessControl::Grant.new(group: @group, **attrs) }
      return invalid(grants) unless @group.valid? & grants.all?(&:valid?)

      refusal = escalation_refusal(stored, compared, desired, new_member_ids - old_member_ids)
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
    # Judged on the list as posted, so two identical entries are "listed
    # twice" too (`normalize_grants` keeps both, in a stable order). There is no
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
      end.sort_by { |grant| [ grant[:permission], grant[:scope].to_json ] }
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
    # The consequence, on purpose: from a non-owner who couldn't hand out the
    # removed name, such a grant is accepted in ONE shape only -- posted back
    # exactly as it is (a rename of the group, a description). This method
    # reads the live scope posted WITHOUT the name as the entry too, so the
    # escalation check has nothing to say about it; but giving the name up is
    # a removal, and `#removal_refusal`, which compares the stored grants with
    # the posted ones raw, refuses it for anyone who couldn't manage the group
    # as it stands. The editor agrees: a group that stores a name its viewer
    # couldn't grant is view-only for them (`AccessControl.can_manage_group?`
    # reads the grants as stored), and Remove is pressed by an owner or by
    # someone whose own grant covers the name. This is the side a request
    # meets, forged or not, however the form is drawn.
    #
    # Members are NOT read through this list. Whether a save may add a member
    # is judged on what the group will store (`#escalation_refusal`), carried
    # names included: this method answers "did the grant change", and handing a
    # grant to someone new is a different question, to which a dormant name is
    # not nothing.
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
    # group, before anything is assigned.
    #
    # Both halves read the grants AS STORED (`LiveGrants#as_stored`), the same
    # list `can_manage_group?` judges. WHETHER something is being taken away:
    # a stored grant that is not in `posted` -- the grants exactly as
    # submitted, not `#live`'s reading of them -- exactly as it stands. So a
    # removed content type's name counts: posting `{blog}` for a stored
    # `{blog, retired}` (the editor's Remove) takes the dormant name away, and
    # posting the form of a group that holds a dead-but-dormant grant
    # (`{retired}` alone, never rendered, so never posted) takes that grant
    # away. Both are removals, and only someone who could grant the name may
    # make them -- which is what makes the editor's view-only state for
    # everyone else true of a forged request too. What still does not count,
    # because it can never come back: a deleted page id (in neither list) and
    # a grant that is dead for good. A form posted as rendered carries every
    # removed name of a live grant, so it removes nothing unless the group
    # holds a dormant dead grant; a save that posts no grants removes none.
    # WHETHER THE ACTOR MAY, once something is: `can_manage_group?`.
    def removal_refusal(stored, posted, removed_member_ids)
      return if @group.new_record? || actor.nil? || AccessControl.owner?(actor)

      removed_grants = posted ? stored.as_stored - posted : []
      return if removed_member_ids.empty? && removed_grants.empty?
      return if AccessControl.can_manage_group?(actor, @group)

      denied("groups.manage", @group)
    end

    # The first refusal, or nil. Owners and trusted code paths (nil actor,
    # already let through by `authorize!`) are never refused; a token --
    # even an owner's -- is judged on its effective rights (final fix wave,
    # Minor 1: `AccessControl.can_grant?` takes the token itself).
    #
    # Two questions, read from two lists on purpose:
    #
    # 1. Is each new or changed grant one the actor could hand out? `compared`
    #    (`#live`) against the stored live grants: an untouched grant is not
    #    re-checked, a changed one is checked raw.
    # 2. With a member ADDED: is every grant the group will hold one the actor
    #    could hand out? That member is handed all of them, whether this save
    #    touched them or not, so the list is what the group will STORE, not
    #    what changed -- `posted`, the grants exactly as submitted (a carried
    #    removed content type still on them), or, when the save posts no grants
    #    at all, the stored grants as `AccessControl.can_assign_group?` judges
    #    them (`LiveGrants#as_stored`: carried names, and a dead grant that a
    #    re-registered type would revive). A removed type's name is dormant,
    #    not gone -- the day a type of that name is registered again it grants,
    #    to this new member too -- so a manager who could only grant "blog"
    #    can't add a member to a group storing `{blog, retired}`: the same
    #    answer `Users::Save` gives for the same membership from the user's
    #    side. A save that posts grants replaces the group's whole list, so a
    #    dead grant (never rendered, never posted) is gone after it and is
    #    rightly not in `posted`.
    def escalation_refusal(stored, compared, posted, added_member_ids)
      return if actor.nil? || AccessControl.owner?(actor)

      unchanged = stored.attributes
      Array(compared).each do |grant|
        next if unchanged.include?(grant)
        return denied(grant[:permission], @group) unless AccessControl.can_grant?(actor, grant[:permission], grant[:scope])
      end

      return if added_member_ids.empty?

      (posted || stored.as_stored).each do |grant|
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
