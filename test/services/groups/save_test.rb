require "test_helper"

# `Groups::Save` (access-control design spec §3.3 "Groups", §5 "Groups
# module"): name, description, members and grants, with the no-escalation
# rule for non-owners (Review Focus 1) and stale grants that never block a
# save (Review Focus 3).
class Groups::SaveTest < ActiveSupport::TestCase
  setup do
    @manager_group = AccessControl::Group.create!(name: "Group managers")
    AccessControl::Membership.create!(user: users(:editor_branch), group: @manager_group)
    grant(@manager_group, "groups.manage")
  end

  test "creates a group with scoped grants and members, and records group.created" do
    result = as_owner do
      Groups::Save.call(attributes: {
        name: "Blog authors", description: "Own blog posts",
        member_ids: [ users(:author).id ],
        grants: [ { permission: "posts.edit", scope: { content_types: [ "blog" ], own: true } }, { permission: "posts.read", scope: {} } ]
      })
    end

    assert result.ok?, result.errors.inspect
    group = result.record
    assert_equal [ users(:author) ], group.users.to_a
    assert_equal [ [ "posts.edit", { "content_types" => [ "blog" ], "own" => true } ], [ "posts.read", {} ] ],
      group.grants.order(:permission).map { |g| [ g.permission, g.scope ] }

    event = Audit::Event.find_by!(action: "group.created", subject: group)
    assert_equal "Blog authors", event.snapshot["name"]
    assert_equal 2, event.snapshot["grants"].size
  end

  # The database's unique index is the guarantee; the service refuses the
  # request first, as malformed input (an ordinary validation failure), not as
  # a right the actor lacks -- so for an owner and a non-owner alike, nothing is
  # written and neither `group.updated` nor `access.denied` is recorded.
  test "a request listing one permission twice is invalid, for an owner and for a non-owner, and writes nothing" do
    group = AccessControl::Group.create!(name: "Twice")
    grant(group, "posts.edit", "content_types" => %w[blog])
    grant(@manager_group, "posts.edit")
    posted = [ { permission: "posts.edit", scope: { content_types: %w[blog] } }, { permission: "posts.edit", scope: { own: true } } ]

    [ nil, users(:editor_branch) ].each do |actor|
      assert_no_difference -> { Audit::Event.count } do
        result = actor ? as(actor) { Groups::Save.call(group, attributes: { name: "Renamed", grants: posted }) } : as_owner { Groups::Save.call(group, attributes: { name: "Renamed", grants: posted }) }

        assert_not result.ok?
        assert_not result.denied?
        assert_includes result.errors, "Edit posts is listed twice."
      end
      assert_equal "Twice", group.reload.name
      assert_equal [ { "content_types" => %w[blog] } ], group.grants.where(permission: "posts.edit").map(&:scope)
    end
  end

  test "two identical entries for one permission are refused as listed twice" do
    group = AccessControl::Group.create!(name: "Identical")

    result = as_owner do
      Groups::Save.call(group, attributes: { name: "Identical", grants: [ { permission: "posts.read", scope: {} }, { permission: "posts.read", scope: {} } ] })
    end

    assert_not result.ok?
    assert_includes result.errors, "Read posts is listed twice."
    assert_empty group.grants.reload
  end

  test "a request that lists one permission twice for a new group creates nothing" do
    assert_no_difference [ -> { AccessControl::Group.count }, -> { AccessControl::Grant.count }, -> { Audit::Event.count } ] do
      result = as_owner do
        Groups::Save.call(attributes: { name: "New twice", grants: [ { permission: "posts.read", scope: {} }, { permission: "posts.read", scope: { own: true } } ] })
      end
      assert_not result.ok?
      assert_not result.denied?
    end
  end

  # Two saves of one group that both pass the up-front check: the loser's insert
  # meets the unique index because the other save's row for that permission is
  # already there. Provoked for real: just before a grant is saved, a second
  # row for the same (group, permission) is written the way a concurrent save
  # would. The answer is a plain failure, not a 500, and nothing is kept.
  test "a unique-index violation while replacing grants is a plain failure and rolls the whole save back" do
    group = AccessControl::Group.create!(name: "Race")
    grant(group, "posts.read")
    original = AccessControl::Grant.instance_method(:save!)
    group_audit = -> { Audit::Event.count }
    AccessControl::Grant.define_method(:save!) do |*args|
      AccessControl::Grant.insert_all!([ { group_id: group_id, permission: permission, scope: {}, created_at: Time.current, updated_at: Time.current } ])
      original.bind_call(self, *args)
    end

    result = nil
    assert_no_difference group_audit do
      result = as_owner { Groups::Save.call(group, attributes: { name: "Renamed", grants: [ { permission: "posts.edit", scope: {} } ] }) }
    end

    assert_not result.ok?
    assert_not result.denied?
    assert_includes result.errors, "This group was changed elsewhere. Reload and try again."
    assert_equal "Race", group.reload.name
    assert_equal [ "posts.read" ], group.grants.pluck(:permission)
  ensure
    AccessControl::Grant.remove_method(:save!)
  end

  test "editing records group.updated with the grant and member changes" do
    group = AccessControl::Group.create!(name: "Writers")
    grant(group, "posts.read")

    result = as_owner do
      Groups::Save.call(group, attributes: {
        name: "Writers", member_ids: [ users(:reader).id ],
        grants: [ { permission: "posts.read", scope: {} }, { permission: "posts.edit", scope: { own: true } } ]
      })
    end

    assert result.ok?, result.errors.inspect
    event = Audit::Event.find_by!(action: "group.updated", subject: group)
    assert_equal [ [], [ users(:reader).id ] ], event.field_changes["member_ids"]
    assert_equal [ { "permission" => "posts.read", "scope" => {} } ], event.field_changes["grants"].first
    assert_includes event.field_changes["grants"].last, { "permission" => "posts.edit", "scope" => { "own" => true } }
  end

  test "attributes left out are left alone" do
    group = AccessControl::Group.create!(name: "Writers")
    grant(group, "posts.read")
    AccessControl::Membership.create!(user: users(:reader), group: group)

    result = as_owner { Groups::Save.call(group, attributes: { description: "Renamed" }) }

    assert result.ok?, result.errors.inspect
    assert_equal [ "posts.read" ], group.grants.pluck(:permission)
    assert_equal [ users(:reader) ], group.users.to_a
  end

  test "an unregistered permission or a malformed scope is a validation failure, not a crash" do
    group = AccessControl::Group.create!(name: "Writers")

    result = as_owner { Groups::Save.call(group, attributes: { grants: [ { permission: "nope.edit", scope: {} } ] }) }
    assert_not result.ok?
    assert_not result.denied?
    assert_match(/isn't a registered permission/, result.errors.to_sentence)

    result = as_owner { Groups::Save.call(group, attributes: { grants: [ { permission: "pages.edit", scope: { content_types: [ "blog" ] } } ] }) }
    assert_not result.ok?
    assert_match(/can't be scoped by content_types/, result.errors.to_sentence)
    assert_empty group.grants.reload
  end

  test "needs groups.manage" do
    result = as(users(:author)) { Groups::Save.call(attributes: { name: "Mine" }) }

    assert result.denied?
    assert_equal [ "You don't have permission to manage groups" ], result.errors
    assert_not AccessControl::Group.exists?(name: "Mine")
  end

  # --- No privilege escalation (Review Focus 1) --------------------------------

  test "a non-owner can't add a permission they lack" do
    group = AccessControl::Group.create!(name: "Others")

    result = as(users(:editor_branch)) do
      Groups::Save.call(group, attributes: { grants: [ { permission: "users.manage", scope: {} } ] })
    end

    assert result.denied?
    assert_equal [ "You don't have permission to manage users" ], result.errors
    assert_empty group.grants.reload
    assert_equal "access.denied", Audit::Event.order(:id).last.action
  end

  test "a non-owner can hand out a permission they hold, at the same or a narrower scope" do
    grant(@manager_group, "posts.edit", "content_types" => %w[blog now_update])
    group = AccessControl::Group.create!(name: "Others")

    result = as(users(:editor_branch)) do
      Groups::Save.call(group, attributes: { grants: [ { permission: "posts.edit", scope: { content_types: [ "blog" ] } } ] })
    end

    assert result.ok?, result.errors.inspect
  end

  test "a non-owner can't widen a scope" do
    grant(@manager_group, "posts.edit", "own" => true)
    group = AccessControl::Group.create!(name: "Others")
    grant(group, "posts.edit", "own" => true)

    result = as(users(:editor_branch)) do
      Groups::Save.call(group, attributes: { grants: [ { permission: "posts.edit", scope: {} } ] })
    end

    assert result.denied?
    assert_equal({ "own" => true }, group.grants.reload.sole.scope)
  end

  # Fix round 1 (M6): a forged branch outside the actor's own root.
  test "a non-owner can't widen a branch scope with a forged page id outside their root" do
    mine = as_owner { create_page(title: "Mine") }
    below = as_owner { create_page(title: "Below", parent: mine) }
    elsewhere = as_owner { create_page(title: "Elsewhere") }
    grant(@manager_group, "pages.edit", "page_ids" => [ mine.id ])
    group = AccessControl::Group.create!(name: "Others")
    grant(group, "pages.edit", "page_ids" => [ below.id ])

    result = as(users(:editor_branch)) do
      Groups::Save.call(group, attributes: { grants: [ { permission: "pages.edit", scope: { page_ids: [ below.id, elsewhere.id ] } } ] })
    end
    assert result.denied?
    assert_equal({ "page_ids" => [ below.id ] }, group.grants.reload.sole.scope)

    widened_within = as(users(:editor_branch)) do
      Groups::Save.call(group, attributes: { grants: [ { permission: "pages.edit", scope: { page_ids: [ mine.id ] } } ] })
    end
    assert widened_within.ok?, widened_within.errors.inspect
  end

  test "a non-owner can't widen a group they're a member of" do
    result = as(users(:editor_branch)) do
      Groups::Save.call(@manager_group, attributes: {
        grants: [ { permission: "groups.manage", scope: {} }, { permission: "settings.manage", scope: {} } ]
      })
    end

    assert result.denied?
    assert_equal [ "groups.manage" ], @manager_group.grants.reload.pluck(:permission)
  end

  test "a non-owner can't add themselves to a group holding permissions they lack" do
    result = as(users(:editor_branch)) do
      Groups::Save.call(access_control_groups(:admin), attributes: { member_ids: [ users(:two).id, users(:editor_branch).id ] })
    end

    assert result.denied?
    assert_not_includes access_control_groups(:admin).users.reload, users(:editor_branch)
  end

  # Final fix wave (Important 2) changed the second half: removing a grant
  # from a group that holds rights the actor lacks is managing that group
  # as it stands, and is refused; renaming it still isn't.
  test "a non-owner can rename a group whatever it holds, but not remove grants from one beyond them" do
    group = AccessControl::Group.create!(name: "Writers")
    grant(group, "posts.read")
    grant(group, "users.manage")
    grants = [ { permission: "posts.read", scope: {} }, { permission: "users.manage", scope: {} } ]

    renamed = as(users(:editor_branch)) { Groups::Save.call(group, attributes: { name: "Scribes", grants: grants }) }
    assert renamed.ok?, renamed.errors.inspect
    assert_equal "Scribes", group.reload.name

    stripped = as(users(:editor_branch)) do
      Groups::Save.call(group, attributes: { grants: [ { permission: "posts.read", scope: {} } ] })
    end
    assert stripped.denied?
    assert_equal %w[posts.read users.manage], group.grants.order(:permission).pluck(:permission)
  end

  test "a built-in group can't be renamed" do
    group = access_control_groups(:editor)

    result = as_owner { Groups::Save.call(group, attributes: { name: "Editors" }) }

    assert_not result.ok?
    assert_equal [ "Name of a built-in group can't be changed" ], result.errors
    assert_equal "Editor", group.reload.name
  end

  test "unchanged grants the actor doesn't hold don't block an edit" do
    group = access_control_groups(:editor)
    grants = group.grants.map { |g| { permission: g.permission, scope: g.scope } }

    result = as(users(:editor_branch)) { Groups::Save.call(group, attributes: { description: "Changed", grants: grants }) }

    assert result.ok?, result.errors.inspect
    assert_equal "Changed", group.reload.description
  end

  test "an owner can do anything" do
    result = as_owner do
      Groups::Save.call(@manager_group, attributes: {
        member_ids: [ users(:one).id ], grants: [ { permission: "users.manage", scope: {} } ]
      })
    end

    assert result.ok?, result.errors.inspect
  end

  # --- Stale grants (Review Focus 3) --------------------------------------------

  test "a stale grant never blocks saving, and its stale values are dropped" do
    page = as_owner { create_page(title: "Gone soon") }
    kept = as_owner { create_page(title: "Kept") }
    group = AccessControl::Group.create!(name: "Stale")
    grant(group, "posts.edit", "content_types" => %w[blog retired_type])
    grant(group, "pages.edit", "page_ids" => [ page.id, kept.id ])
    grant(group, "pages.read", "page_ids" => [ page.id ])
    as_owner { delete_for_good(page) }

    live = AccessControl::LiveGrants.new(group.grants.reload.to_a)
    submitted = live.attributes

    # The editor re-submits what it showed: the live values only. The
    # manager holds none of these permissions, but nothing is new.
    result = as(users(:editor_branch)) { Groups::Save.call(group, attributes: { name: "Stale", grants: submitted }) }

    assert result.ok?, result.errors.inspect
    assert_equal [ [ "pages.edit", { "page_ids" => [ kept.id ] } ], [ "posts.edit", { "content_types" => [ "blog" ] } ] ],
      group.grants.reload.order(:permission).map { |g| [ g.permission, g.scope ] }
  end

  # Round 3 (Task 10): the editor now CARRIES a removed content type
  # (a hidden input, until the editor presses Remove) so an untouched save
  # changes nothing -- the carried value is a dead scope value, not a change.
  test "an unchanged save that carries a removed content type changes nothing, even for a non-owner" do
    group = AccessControl::Group.create!(name: "Carrying")
    grant(group, "posts.edit", "content_types" => %w[blog retired_type], "own" => true)
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])
    AccessControl::Membership.create!(user: users(:author), group: group) # a member the manager can't hand to
    carried = group.grants.map { |g| { permission: g.permission, scope: g.scope } }

    assert_no_difference -> { Audit::Event.count } do
      result = as(users(:editor_branch)) { Groups::Save.call(group, attributes: { name: "Carrying", grants: carried }) }
      assert result.ok?, result.errors.inspect
    end
    assert_equal [ { "content_types" => %w[blog retired_type], "own" => true } ], group.grants.reload.map(&:scope)
  end

  test "dropping the carried removed type is the explicit change, and narrowing is not charged for it" do
    group = AccessControl::Group.create!(name: "Dropping")
    grant(group, "posts.edit", "content_types" => %w[blog retired_type])
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])

    result = as(users(:editor_branch)) do
      Groups::Save.call(group, attributes: { name: "Dropping", grants: [ { permission: "posts.edit", scope: { content_types: %w[blog] } } ] })
    end

    assert result.ok?, result.errors.inspect
    assert_equal [ { "content_types" => %w[blog] } ], group.grants.reload.map(&:scope)
    assert_equal 1, Audit::Event.where(action: "group.updated", subject_id: group.id).count
  end

  test "a carried removed type does not let a non-owner widen a grant they can't hand out" do
    group = AccessControl::Group.create!(name: "Widening")
    grant(group, "posts.edit", "content_types" => %w[blog retired_type])
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])

    result = as(users(:editor_branch)) do
      Groups::Save.call(group, attributes: { name: "Widening", grants: [ { permission: "posts.edit", scope: { content_types: %w[blog now_update retired_type] } } ] })
    end

    assert result.denied?
    assert_equal [ { "content_types" => %w[blog retired_type] } ], group.grants.reload.map(&:scope)
  end

  # --- Fix round 1 (C1): only what the editor CARRIES is ignored ----------------
  # An unregistered name is dormant until a plugin registers it, then it grants.
  # Only a name the STORED grant of the same permission already holds as gone may
  # be left out of the comparisons; any other goes through the rules.

  test "a non-owner can't plant an unregistered type name in a grant they could only hand out as blog" do
    group = AccessControl::Group.create!(name: "Planting")
    grant(group, "posts.edit", "content_types" => %w[blog])
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])

    result = as(users(:editor_branch)) do
      Groups::Save.call(group, attributes: { name: "Planting", grants: [ { permission: "posts.edit", scope: { content_types: %w[blog ghost] } } ] })
    end

    assert result.denied?
    assert_equal [ { "content_types" => %w[blog] } ], group.grants.reload.map(&:scope)
    assert_equal 1, Audit::Event.where(action: "access.denied").count
  end

  test "a blog-only holder can't add a new grant carrying an unregistered type" do
    group = AccessControl::Group.create!(name: "Fresh")
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])

    result = as(users(:editor_branch)) do
      Groups::Save.call(group, attributes: { name: "Fresh", grants: [ { permission: "posts.edit", scope: { content_types: %w[blog acme/events] } } ] })
    end

    assert result.denied?
    assert_empty group.grants.reload
    assert_equal 1, Audit::Event.where(action: "access.denied").sum(:occurrences)
  end

  test "a stored retired type is carried, but an extra unregistered name beside it is refused; untouched still saves quietly" do
    group = AccessControl::Group.create!(name: "Both")
    grant(group, "posts.edit", "content_types" => %w[blog retired])
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])

    widened = as(users(:editor_branch)) do
      Groups::Save.call(group, attributes: { name: "Both", grants: [ { permission: "posts.edit", scope: { content_types: %w[blog retired ghost] } } ] })
    end
    assert widened.denied?
    assert_equal [ { "content_types" => %w[blog retired] } ], group.grants.reload.map(&:scope)
    assert_equal 1, Audit::Event.where(action: "access.denied").sum(:occurrences)

    assert_no_difference -> { Audit::Event.count } do
      untouched = as(users(:editor_branch)) do
        Groups::Save.call(group, attributes: { name: "Both", grants: [ { permission: "posts.edit", scope: { content_types: %w[blog retired] } } ] })
      end
      assert untouched.ok?, untouched.errors.inspect
    end
  end

  test "an owner may still store what they post" do
    group = AccessControl::Group.create!(name: "Owned")
    grant(group, "posts.edit", "content_types" => %w[blog])

    result = as_owner { Groups::Save.call(group, attributes: { name: "Owned", grants: [ { permission: "posts.edit", scope: { content_types: %w[blog ghost] } } ] }) }

    assert result.ok?
    assert_equal [ { "content_types" => %w[blog ghost] } ], group.grants.reload.map(&:scope)
  end

  # --- Fix round 2: a carried name is ignored only in an otherwise UNCHANGED grant --
  # Fix round 1 keyed the strip by permission and name alone, so a removed type
  # the group already held rode along while the REST of the grant changed -- and
  # the stripped form, not what would be stored, went to `can_grant?`. Each of
  # A-D below returned ok that way, and each was refused before Task 10 (the raw
  # scope went to `can_grant?`). The dormant right they widen ("retired" for
  # every post rather than the user's own; "retired" on a grant that had none)
  # becomes a real one the day a plugin registers that name again.

  test "A: unticking Own only on a grant that carries a removed type is refused for a non-owner who can't grant that name" do
    group = AccessControl::Group.create!(name: "A")
    grant(group, "posts.edit", "content_types" => %w[blog retired], "own" => true)
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])

    assert_refused_unchanged(group) do
      Groups::Save.call(group, attributes: { name: "A", grants: [ { permission: "posts.edit", scope: { content_types: %w[blog retired] } } ] })
    end
  end

  # Final fix wave (Task 10 re-review, c): every refusal above is the
  # ESCALATION check's. Here it has nothing to say -- the actor holds `{own:
  # true}`, which covers `{[blog, retired], own: true}` -- and the posted grant
  # is not the stored one read back (`#live`: its scope minus the removed name
  # is `{[blog], own}`, not the entry's `{[blog]}`). So the stored `{[blog]}`
  # counts as removed (narrowing is a removal), and the refusal comes from
  # `#removal_refusal` alone: the actor couldn't hand out the group as it
  # stands.
  test "narrowing a grant that carries a removed type is refused by the removal check alone, for an actor the escalation check lets through" do
    group = AccessControl::Group.create!(name: "Narrowed")
    grant(group, "posts.edit", "content_types" => %w[blog retired])
    grant(@manager_group, "posts.edit", "own" => true)
    posted = { permission: "posts.edit", scope: { content_types: %w[blog retired], own: true } }

    as(users(:editor_branch)) do
      assert AccessControl.can_grant?(users(:editor_branch), "posts.edit", { "content_types" => %w[blog retired], "own" => true }), "the escalation check must have nothing to refuse"
      assert_not AccessControl.can_manage_group?(users(:editor_branch), group)
    end

    assert_refused_unchanged(group) do
      Groups::Save.call(group, attributes: { name: "Narrowed", grants: [ posted ] })
    end
    assert_equal "groups.manage", Audit::Event.where(action: "access.denied").order(:id).last.metadata["permission"]
  end

  # `LiveGrants` files a grant whose every type is gone under `dead`; the editor
  # never renders or submits it, so nothing of it is "carried".
  test "B: a dead grant's removed type can't be revived inside a wider live grant" do
    group = AccessControl::Group.create!(name: "B")
    grant(group, "posts.edit", "content_types" => %w[retired], "own" => true)
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])

    assert_refused_unchanged(group) do
      Groups::Save.call(group, attributes: { name: "B", grants: [ { permission: "posts.edit", scope: { content_types: %w[blog retired] } } ] })
    end
  end

  test "D: a dead grant can't be reposted without its Own only" do
    group = AccessControl::Group.create!(name: "D")
    grant(group, "posts.edit", "content_types" => %w[retired], "own" => true)
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])

    assert_refused_unchanged(group) do
      Groups::Save.call(group, attributes: { name: "D", grants: [ { permission: "posts.edit", scope: { content_types: %w[retired] } } ] })
    end
  end

  test "a removed type can't ride along while a live type is added or swapped" do
    group = AccessControl::Group.create!(name: "Swap")
    grant(group, "posts.edit", "content_types" => %w[blog retired])
    grant(@manager_group, "posts.edit", "content_types" => %w[blog now_update])

    [ %w[blog now_update retired], %w[now_update retired] ].each do |types|
      assert_refused_unchanged(group) do
        Groups::Save.call(group, attributes: { name: "Swap", grants: [ { permission: "posts.edit", scope: { content_types: types } } ] })
      end
    end
  end

  # A stored grant's removed names can't be dealt out over several posted grants:
  # the request lists the permission twice, which is refused before any right is
  # compared (an invalid request, not a denied one).
  test "a stored grant with two removed types can't be split into two grants that each carry one" do
    group = AccessControl::Group.create!(name: "Split")
    grant(group, "posts.edit", "content_types" => %w[blog retired vanished], "own" => true)
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])
    before = group.grants.reload.map { |g| [ g.id, g.scope ] }

    assert_no_difference -> { Audit::Event.count } do
      result = as(users(:editor_branch)) do
        Groups::Save.call(group, attributes: { name: "Split", grants: [
          { permission: "posts.edit", scope: { content_types: %w[blog retired], own: true } },
          { permission: "posts.edit", scope: { content_types: %w[blog vanished], own: true } }
        ] })
      end
      assert_not result.ok?
      assert_not result.denied?
    end
    assert_equal before, group.grants.reload.map { |g| [ g.id, g.scope ] }
  end

  test "a removed type one permission's grant holds can't be planted in another permission's grant" do
    group = AccessControl::Group.create!(name: "Across")
    grant(group, "posts.edit", "content_types" => %w[blog retired])
    grant(group, "posts.publish", "content_types" => %w[blog])
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])
    grant(@manager_group, "posts.publish", "content_types" => %w[blog])

    assert_refused_unchanged(group) do
      Groups::Save.call(group, attributes: { name: "Across", grants: [
        { permission: "posts.edit", scope: { content_types: %w[blog retired] } },
        { permission: "posts.publish", scope: { content_types: %w[blog retired] } }
      ] })
    end
  end

  test "an ApiToken takes the same path: A is refused for a token too" do
    token_group = AccessControl::Group.create!(name: "Token group")
    grant(token_group, "groups.manage")
    grant(token_group, "posts.edit", "content_types" => %w[blog])
    token, = ApiToken.generate!(users(:one), group: token_group)
    group = AccessControl::Group.create!(name: "A by token")
    grant(group, "posts.edit", "content_types" => %w[blog retired], "own" => true)

    assert_refused_unchanged(group, actor: token, channel: :mcp) do
      Groups::Save.call(group, attributes: { name: "A by token", grants: [ { permission: "posts.edit", scope: { content_types: %w[blog retired] } } ] })
    end

    assert_no_difference -> { Audit::Event.count } do
      untouched = as(token, channel: :mcp) do
        Groups::Save.call(group, attributes: { name: "A by token", grants: [ { permission: "posts.edit", scope: { content_types: %w[blog retired], own: true } } ] })
      end
      assert untouched.ok?, untouched.errors.inspect
    end
  end

  test "a name that only looks like the carried one is not the carried one" do
    group = AccessControl::Group.create!(name: "Variants")
    grant(group, "posts.edit", "content_types" => %w[blog retired])
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])

    [ %w[blog retired Retired], [ "blog", "retired", " retired" ], [ "blog", "retired", [ "retired" ] ], %w[blog Retired] ].each do |types|
      assert_refused_unchanged(group) do
        Groups::Save.call(group, attributes: { name: "Variants", grants: [ { permission: "posts.edit", scope: { content_types: types } } ] })
      end
    end
  end

  test "the carried name posted twice, or in another order, is still the untouched grant" do
    group = AccessControl::Group.create!(name: "Twice")
    grant(group, "posts.edit", "content_types" => %w[blog retired], "own" => true)
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])
    before = raw_grants(group)

    [ %w[blog retired retired], %w[retired blog] ].each do |types|
      assert_no_difference -> { Audit::Event.count } do
        result = as(users(:editor_branch)) do
          Groups::Save.call(group, attributes: { name: "Twice", grants: [ { permission: "posts.edit", scope: { "own" => "1", "content_types" => types } } ] })
        end
        assert result.ok?, result.errors.inspect
      end
      assert_equal before, raw_grants(group)
    end
  end

  test "an untouched save of a group whose grants carry removed types changes nothing for a non-owner: with own, without it, beside page ids" do
    kept = as_owner { create_page(title: "Kept") }
    group = AccessControl::Group.create!(name: "Untouched")
    grant(group, "posts.edit", "content_types" => %w[blog retired], "own" => true)
    grant(group, "posts.publish", "content_types" => %w[blog retired])
    grant(group, "posts.read", "content_types" => %w[retired]) # dead: never rendered, never submitted
    grant(group, "pages.edit", "page_ids" => [ kept.id ])
    before = raw_grants(group)
    submitted = AccessControl::LiveGrants.new(group.grants.to_a).carried_attributes # what the editor renders

    assert_equal [ %w[blog retired], %w[blog retired] ], submitted.filter_map { |g| g[:scope]["content_types"] }
    # The manager holds none of these permissions: nothing here is theirs to hand out.
    assert_no_difference -> { Audit::Event.where(action: "access.denied").count } do
      result = as(users(:editor_branch)) { Groups::Save.call(group, attributes: { name: "Untouched", grants: submitted }) }
      assert result.ok?, result.errors.inspect
    end
    # The dead grant is dropped, as on every save since before Task 10; the rest is as stored.
    assert_equal before.reject { |_, scope| scope == { "content_types" => %w[retired] } }, raw_grants(group)
  end

  # Membership changes are judged on the grants AS STORED, removed content
  # types included. Adding a member hands them every grant of the group, and a
  # removed name is dormant, not gone -- it grants again the day a type of that
  # name is registered -- so a manager who could only grant "blog" can't add a
  # member to a group that still stores "retired" beside it, however the grants
  # are posted: as rendered (the name carried), or not at all. Taking a member
  # out is managing the group as it stands (`can_manage_group?`), which reads
  # the stored grants the same way.
  test "adding a member to a group that carries a removed type, grants as rendered, is refused for a manager who couldn't grant the name" do
    group = AccessControl::Group.create!(name: "Members")
    grant(group, "posts.edit", "content_types" => %w[blog retired], "own" => true)
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])
    as_rendered = AccessControl::LiveGrants.new(group.grants.to_a).carried_attributes
    assert_equal [ { permission: "posts.edit", scope: { "content_types" => %w[blog retired], "own" => true } } ], as_rendered

    assert_refused_unchanged(group) do
      Groups::Save.call(group, attributes: { name: "Members", member_ids: [ users(:reader).id ], grants: as_rendered })
    end
    assert_empty group.reload.user_ids
    denial = Audit::Event.where(action: "access.denied").order(:id).last
    assert_equal "posts.edit", denial.metadata["permission"]
  end

  test "a members-only save can't add a member to a group that stores a removed type the manager couldn't grant: beside a live type, or alone" do
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])

    [ %w[blog retired], %w[retired] ].each_with_index do |types, index|
      group = AccessControl::Group.create!(name: "Members only #{index}")
      grant(group, "posts.edit", "content_types" => types)

      assert_refused_unchanged(group) do
        Groups::Save.call(group, attributes: { member_ids: [ users(:reader).id ] })
      end
      assert_empty group.reload.user_ids, types.inspect
    end
  end

  test "removing a member from a group that stores a removed type is refused for a manager who couldn't grant the name: grants as rendered, or none posted" do
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])

    [ %w[blog retired], %w[retired] ].each_with_index do |types, index|
      group = AccessControl::Group.create!(name: "Leaving #{index}")
      grant(group, "posts.edit", "content_types" => types)
      AccessControl::Membership.create!(user: users(:reader), group: group)
      as_rendered = AccessControl::LiveGrants.new(group.grants.to_a).carried_attributes

      [ { member_ids: [] }, { member_ids: [], grants: as_rendered } ].each do |attributes|
        # A wholly dead grant is never rendered: posting the form drops it, which
        # is no removal by itself -- the member leaving is.
        assert_refused_unchanged(group) { Groups::Save.call(group, attributes: attributes) }
        assert_equal [ users(:reader).id ], group.reload.user_ids, "#{types.inspect} #{attributes.keys.inspect}"
      end
    end
  end

  # The form never renders a wholly dead grant, so a save of the form drops it:
  # the member added in that same save is handed what the save stores, and the
  # dormant name is not in it.
  test "adding a member in a save that drops a dead grant hands them only what is stored afterwards" do
    group = AccessControl::Group.create!(name: "Dead and live")
    grant(group, "posts.edit", "content_types" => %w[blog])
    grant(group, "posts.read", "content_types" => %w[retired])
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])
    as_rendered = AccessControl::LiveGrants.new(group.grants.to_a).carried_attributes
    assert_equal [ { permission: "posts.edit", scope: { "content_types" => %w[blog] } } ], as_rendered

    assert_no_difference -> { Audit::Event.where(action: "access.denied").count } do
      result = as(users(:editor_branch)) { Groups::Save.call(group, attributes: { member_ids: [ users(:reader).id ], grants: as_rendered }) }
      assert result.ok?, result.errors.inspect
    end
    assert_equal [ users(:reader).id ], group.reload.user_ids
    assert_equal [ [ "posts.edit", { "content_types" => %w[blog] } ] ], raw_grants(group)
  end

  test "a manager who could grant the removed name -- unscoped, or their own grant names it -- adds and removes members, grants as rendered: one group.updated, no denial" do
    [ {}, { "content_types" => %w[blog retired] } ].each_with_index do |held, round|
      @manager_group.grants.where(permission: "posts.edit").destroy_all
      grant(@manager_group, "posts.edit", held)
      AccessControl::ActorGrants.reset!
      group = AccessControl::Group.create!(name: "Members #{round}")
      grant(group, "posts.edit", "content_types" => %w[blog retired], "own" => true)
      before = raw_grants(group)
      as_rendered = AccessControl::LiveGrants.new(group.grants.to_a).carried_attributes

      [ [ users(:reader).id ], [] ].each_with_index do |member_ids, index|
        assert_no_difference -> { Audit::Event.where(action: "access.denied").count } do
          result = as(users(:editor_branch)) { Groups::Save.call(group, attributes: { name: group.name, member_ids: member_ids, grants: as_rendered }) }
          assert result.ok?, "#{held.inspect}: #{result.errors.inspect}"
        end
        assert_equal member_ids, group.reload.user_ids
        assert_equal before, raw_grants(group)
        # One `group.updated` per save (the second coalesces into the first's row), members only.
        events = Audit::Event.where(action: "group.updated", subject_id: group.id)
        assert_equal index + 1, events.sum(:occurrences)
        assert_equal [ "member_ids" ], events.sole.field_changes.keys
      end
    end
  end

  test "an ApiToken adding a member to a group that carries a removed type is judged on its group, even an owner's" do
    token_group = AccessControl::Group.create!(name: "Token group")
    grant(token_group, "groups.manage")
    grant(token_group, "posts.edit", "content_types" => %w[blog])
    token, = ApiToken.generate!(users(:one), group: token_group)
    group = AccessControl::Group.create!(name: "Token members")
    grant(group, "posts.edit", "content_types" => %w[blog retired])

    assert_refused_unchanged(group, actor: token, channel: :mcp) do
      Groups::Save.call(group, attributes: { member_ids: [ users(:reader).id ] })
    end
    assert_empty group.reload.user_ids
  end

  test "a trusted code path and an owner add a member to a group that carries a removed type" do
    group = AccessControl::Group.create!(name: "Trusted")
    grant(group, "posts.edit", "content_types" => %w[blog retired])

    assert Groups::Save.call(group, attributes: { member_ids: [ users(:reader).id ] }, actor: nil).ok?
    assert as_owner { Groups::Save.call(group, attributes: { member_ids: [ users(:reader).id, users(:author).id ] }) }.ok?
    assert_equal [ users(:author).id, users(:reader).id ].sort, group.reload.user_ids.sort

    refused = as(nil, channel: :admin) { Groups::Save.call(group, attributes: { member_ids: [] }) }
    assert refused.denied?
  end

  # ...but not when the grant changed in the same save: then it is judged raw,
  # for the grant and for the member it would be handed to.
  test "adding a member while changing a grant that carries a removed type is refused" do
    group = AccessControl::Group.create!(name: "Members and more")
    grant(group, "posts.edit", "content_types" => %w[blog retired], "own" => true)
    grant(@manager_group, "posts.edit", "content_types" => %w[blog])

    assert_refused_unchanged(group) do
      Groups::Save.call(group, attributes: { name: "Members and more", member_ids: [ users(:reader).id ],
        grants: [ { permission: "posts.edit", scope: { content_types: %w[blog retired] } } ] })
    end
    assert_empty group.reload.user_ids
  end

  test "Remove on one of two carried types: that name gone, the other kept, no denial" do
    group = AccessControl::Group.create!(name: "One of two")
    grant(group, "posts.edit", "content_types" => %w[blog retired vanished], "own" => true)

    assert_no_difference -> { Audit::Event.where(action: "access.denied").count } do
      result = as(users(:editor_branch)) do
        Groups::Save.call(group, attributes: { name: "One of two", grants: [ { permission: "posts.edit", scope: { content_types: %w[blog vanished], own: true } } ] })
      end
      assert result.ok?, result.errors.inspect
    end
    assert_equal [ { "content_types" => %w[blog vanished], "own" => true } ], group.grants.reload.map(&:scope)
    assert_equal 1, Audit::Event.where(action: "group.updated", subject_id: group.id).count
  end

  test "Remove by a non-owner who holds nothing of the permission: stored without the name, one group.updated, no denial" do
    group = AccessControl::Group.create!(name: "Removing")
    grant(group, "posts.edit", "content_types" => %w[blog retired], "own" => true)

    assert_no_difference -> { Audit::Event.where(action: "access.denied").count } do
      result = as(users(:editor_branch)) do
        Groups::Save.call(group, attributes: { name: "Removing", grants: [ { permission: "posts.edit", scope: { content_types: %w[blog], own: true } } ] })
      end
      assert result.ok?, result.errors.inspect
    end
    assert_equal [ { "content_types" => %w[blog], "own" => true } ], group.grants.reload.map(&:scope)
    assert_equal 1, Audit::Event.where(action: "group.updated", subject_id: group.id).count
  end

  # Someone who could hand out the removed name anyway (an unscoped holder) may
  # change the grant with the name still on it: the raw scope passes `can_grant?`.
  test "a non-owner who holds the permission unscoped may change a grant that carries a removed type" do
    group = AccessControl::Group.create!(name: "Unscoped holder")
    grant(group, "posts.edit", "content_types" => %w[blog retired], "own" => true)
    grant(@manager_group, "posts.edit")

    result = as(users(:editor_branch)) do
      Groups::Save.call(group, attributes: { name: "Unscoped holder", grants: [ { permission: "posts.edit", scope: { content_types: %w[blog retired] } } ] })
    end

    assert result.ok?, result.errors.inspect
    assert_equal [ { "content_types" => %w[blog retired] } ], group.grants.reload.map(&:scope)
  end

  private

  def raw_grants(group) = group.grants.reload.map { |g| [ g.permission, g.scope ] }.sort_by(&:to_json)

  # The block's save is denied: the stored grants are exactly as they were,
  # EXACTLY one `access.denied` is recorded (one row, counted once -- a second
  # denial would coalesce into the row and show in `occurrences`), and no
  # `group.updated`.
  def assert_refused_unchanged(group, actor: users(:editor_branch), channel: :admin, &block)
    before = group.grants.reload.order(:id).map { |g| [ g.id, g.permission, g.scope ] }
    denials = Audit::Event.where(action: "access.denied")
    occurrences_before = denials.sum(:occurrences)
    updates_before = Audit::Event.where(action: "group.updated").count

    result = as(actor, channel: channel, &block)

    assert result.denied?, "expected a denial, got ok=#{result.ok?} errors=#{result.errors.inspect} stored=#{group.grants.reload.map(&:scope).inspect}"
    assert_equal before, group.grants.reload.order(:id).map { |g| [ g.id, g.permission, g.scope ] }
    assert_equal occurrences_before + 1, denials.sum(:occurrences), "exactly one access.denied"
    assert_equal updates_before, Audit::Event.where(action: "group.updated").count
  end

  def grant(group, permission, scope = {})
    AccessControl::Grant.create!(group: group, permission: permission, scope: scope)
  end
  # --- Final fix wave (Important 2): managing a group as it stands -------------

  test "a group manager can't remove members from or strip grants off a group beyond their rights" do
    admin = access_control_groups(:admin)
    members = admin.user_ids.sort
    grants = admin.grants.map { |g| { permission: g.permission, scope: g.scope } }

    removed = as(users(:editor_branch)) { Groups::Save.call(admin, attributes: { member_ids: [] }) }
    stripped = as(users(:editor_branch)) do
      Groups::Save.call(admin, attributes: { grants: grants.reject { |g| g[:permission] == "users.manage" } })
    end

    [ removed, stripped ].each do |result|
      assert result.denied?
      assert_equal [ "You don't have permission to manage groups" ], result.errors
    end
    assert_equal members, admin.reload.user_ids.sort
    assert admin.grants.exists?(permission: "users.manage")
    # Both refusals, coalesced into one row (same actor, action, subject).
    assert Audit::Event.exists?(action: "access.denied", subject: admin)
  end

  test "narrowing a grant counts as removing it" do
    group = AccessControl::Group.create!(name: "Editors of everything")
    grant(group, "posts.edit")
    grant(@manager_group, "posts.edit", { "own" => true })

    result = as(users(:editor_branch)) do
      Groups::Save.call(group, attributes: { grants: [ { permission: "posts.edit", scope: { own: true } } ] })
    end

    assert result.denied?
    assert_equal [ {} ], group.grants.reload.map(&:scope)
  end

  test "a group manager removes members and grants from a group within their rights" do
    group = AccessControl::Group.create!(name: "Readers")
    grant(group, "posts.read")
    grant(group, "pages.read")
    grant(@manager_group, "posts.read")
    grant(@manager_group, "pages.read")
    AccessControl::Membership.create!(user: users(:reader), group: group)

    result = as(users(:editor_branch)) do
      Groups::Save.call(group, attributes: { member_ids: [], grants: [ { permission: "posts.read", scope: {} } ] })
    end

    assert result.ok?, result.errors.inspect
    assert_empty group.reload.user_ids
    assert_equal [ "posts.read" ], group.grants.pluck(:permission)
  end

  # --- Final fix wave (Minor 1): a token is never an owner ----------------------

  test "an owner's token grants only within its own group" do
    token_group = AccessControl::Group.create!(name: "Token group")
    grant(token_group, "groups.manage")
    grant(token_group, "posts.read")
    token, = ApiToken.generate!(users(:one), group: token_group)

    result = as(token, channel: :mcp) do
      Groups::Save.call(attributes: { name: "Widened", grants: [ { permission: "posts.edit", scope: {} } ] })
    end
    assert result.denied?
    assert_not AccessControl::Group.exists?(name: "Widened")

    within = as(token, channel: :mcp) do
      Groups::Save.call(attributes: { name: "Narrow", grants: [ { permission: "posts.read", scope: {} } ] })
    end
    assert within.ok?, within.errors.inspect
  end
end
