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

  private

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
