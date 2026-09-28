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

  test "a non-owner can edit a group's name and remove grants they don't hold" do
    group = AccessControl::Group.create!(name: "Writers")
    grant(group, "posts.read")
    grant(group, "users.manage")

    result = as(users(:editor_branch)) do
      Groups::Save.call(group, attributes: { name: "Scribes", grants: [ { permission: "posts.read", scope: {} } ] })
    end

    assert result.ok?, result.errors.inspect
    assert_equal "Scribes", group.reload.name
    assert_equal [ "posts.read" ], group.grants.pluck(:permission)
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
    as_owner { Pages::Destroy.call(page) }

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
end
