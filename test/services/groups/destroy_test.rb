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
    ApiToken.generate!(users(:one), group: group)
    managers = AccessControl::Group.create!(name: "Group managers")
    AccessControl::Grant.create!(group: managers, permission: "groups.manage", scope: {})
    AccessControl::Membership.create!(user: users(:reader), group: managers)

    assert as(users(:reader)) { Groups::Destroy.call(group) }.ok?

    refused = as(users(:author)) { Groups::Destroy.call(access_control_groups(:branch_editors)) }
    assert refused.denied?
    assert_equal [ "You don't have permission to manage groups" ], refused.errors
  end
end
