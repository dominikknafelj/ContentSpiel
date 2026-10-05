require "test_helper"

class Groups::DestroyTest < ActiveSupport::TestCase
  test "a built-in group can't be deleted" do
    group = access_control_groups(:read_only)

    result = as_owner { Groups::Destroy.call(group) }

    assert_not result.ok?
    assert_equal [ "Built-in groups can't be deleted" ], result.errors
    assert AccessControl::Group.exists?(group.id)
  end

  test "deleting a group revokes its tokens, one token.revoked each, then group.deleted" do
    group = AccessControl::Group.create!(name: "Bots")
    AccessControl::Grant.create!(group: group, permission: "posts.read", scope: {})
    first, first_raw = ApiToken.generate!(users(:reader), group: group)
    second, = ApiToken.generate!(users(:author), group: group)
    old, = ApiToken.generate!(users(:author), group: group)
    old.revoke!
    other, = ApiToken.generate!(users(:author), group: access_control_groups(:read_only))

    result = as(users(:two)) { Groups::Destroy.call(group) }

    assert result.ok?, result.errors.inspect
    assert_not AccessControl::Group.exists?(group.id)
    assert_nil ApiToken.authenticate(first_raw)
    assert_equal [ first.id, second.id ].sort, Audit::Event.where(action: "token.revoked").pluck(:subject_id).sort
    assert Audit::Event.exists?(action: "group.deleted", subject_type: "AccessControl::Group", subject_id: group.id)
    assert_nil other.reload.revoked_at
  end

  test "needs groups.manage, but not tokens.manage, to revoke the group's tokens" do
    group = AccessControl::Group.create!(name: "Bots")
    token, raw = ApiToken.generate!(users(:one), group: group)
    managers = AccessControl::Group.create!(name: "Group managers")
    AccessControl::Grant.create!(group: managers, permission: "groups.manage", scope: {})
    AccessControl::Membership.create!(user: users(:reader), group: managers)

    assert as(users(:reader)) { Groups::Destroy.call(group) }.ok?
    assert_nil ApiToken.authenticate(raw)
    event = Audit::Event.find_by!(action: "token.revoked", subject_type: "ApiToken", subject_id: token.id)
    assert_equal users(:reader).id, event.user_id
    assert_equal({ "reason" => "group deleted" }, event.metadata)

    refused = as(users(:author)) { Groups::Destroy.call(access_control_groups(:branch_editors)) }
    assert refused.denied?
    assert_equal [ "You don't have permission to manage groups" ], refused.errors
  end

  # Fix round 1 (M2): the group-delete path only covers that group's tokens.
  test "revoking on behalf of a group delete doesn't reach another group's token" do
    managers = AccessControl::Group.create!(name: "Group managers")
    AccessControl::Grant.create!(group: managers, permission: "groups.manage", scope: {})
    AccessControl::Membership.create!(user: users(:reader), group: managers)
    other_token, = ApiToken.generate!(users(:one), group: access_control_groups(:admin))

    result = as(users(:reader)) { ApiTokens::Revoke.call(other_token, deleting_group: managers) }

    assert result.denied?
    assert_equal [ "You don't have permission to manage tokens" ], result.errors
    assert_nil other_token.reload.revoked_at
  end
  # Final fix wave (Important 2): deleting a group needs the right to
  # manage it as it stands -- every grant it holds, held by the actor.
  test "a group manager can't delete a group beyond their rights, but can one within them" do
    managers = AccessControl::Group.create!(name: "Group managers")
    AccessControl::Grant.create!(group: managers, permission: "groups.manage", scope: {})
    AccessControl::Grant.create!(group: managers, permission: "posts.read", scope: {})
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)
    powerful = AccessControl::Group.create!(name: "Powerful")
    AccessControl::Grant.create!(group: powerful, permission: "users.manage", scope: {})
    readers = AccessControl::Group.create!(name: "Readers")
    AccessControl::Grant.create!(group: readers, permission: "posts.read", scope: {})

    as(users(:editor_branch)) do
      [ powerful, access_control_groups(:admin) ].each do |group|
        result = Groups::Destroy.call(group)
        assert result.denied?
        assert_equal [ "You don't have permission to manage groups" ], result.errors
        assert AccessControl::Group.exists?(group.id)
      end

      assert Groups::Destroy.call(readers).ok?
    end
    assert_not AccessControl::Group.exists?(readers.id)
    assert_equal 2, Audit::Event.where(action: "access.denied").count
  end

  # A removed content type's name is dormant, not gone: the group is judged as
  # stored, so deleting it takes someone who could grant that name.
  [ %w[blog retired_type], %w[retired_type] ].each do |types|
    test "a manager who could only grant blog can't delete a group storing #{types.inspect}; an unscoped holder can" do
      managers = AccessControl::Group.create!(name: "Group managers")
      AccessControl::Grant.create!(group: managers, permission: "groups.manage", scope: {})
      held = AccessControl::Grant.create!(group: managers, permission: "posts.edit", scope: { "content_types" => %w[blog] })
      AccessControl::Membership.create!(user: users(:editor_branch), group: managers)
      carrying = AccessControl::Group.create!(name: "Carrying")
      AccessControl::Grant.create!(group: carrying, permission: "posts.edit", scope: { "content_types" => types })

      assert_difference -> { Audit::Event.where(action: "access.denied").sum(:occurrences) }, 1 do
        result = as(users(:editor_branch)) { Groups::Destroy.call(carrying) }
        assert result.denied?
      end
      assert AccessControl::Group.exists?(carrying.id)

      held.update!(scope: {})
      AccessControl::ActorGrants.reset!
      assert as(users(:editor_branch)) { Groups::Destroy.call(carrying) }.ok?
      assert_not AccessControl::Group.exists?(carrying.id)
    end
  end
end
