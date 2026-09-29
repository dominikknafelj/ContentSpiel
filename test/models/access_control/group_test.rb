require "test_helper"

class AccessControl::GroupTest < ActiveSupport::TestCase
  test "name must be unique, case-insensitively" do
    AccessControl::Group.create!(name: "Reviewers")

    duplicate = AccessControl::Group.new(name: "REVIEWERS")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "a built-in group can't be destroyed" do
    admin = access_control_groups(:admin)

    assert_not admin.destroy
    assert_includes admin.errors[:base], "built-in groups can't be deleted"
    assert AccessControl::Group.exists?(admin.id)
  end

  test "a built-in group's grants can still change" do
    admin = access_control_groups(:admin)

    grant = admin.grants.find_by!(permission: "audit.view")

    assert grant.destroy
  end

  test "a non-built-in group can be destroyed" do
    branch_editors = access_control_groups(:branch_editors)

    assert branch_editors.destroy
    assert_not AccessControl::Group.exists?(branch_editors.id)
  end

  test "destroying a group destroys its memberships and grants" do
    branch_editors = access_control_groups(:branch_editors)
    membership = branch_editors.memberships.create!(user: users(:reader))
    grant = branch_editors.grants.create!(permission: "pages.read", scope: {})

    branch_editors.destroy!

    assert_not AccessControl::Membership.exists?(membership.id)
    assert_not AccessControl::Grant.exists?(grant.id)
  end
end
