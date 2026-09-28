require "test_helper"

class Users::SaveTest < ActiveSupport::TestCase
  test "a blank password leaves the password alone" do
    user = users(:one)
    result = Users::Save.call(user, attributes: { email_address: "new@example.com", password: "", password_confirmation: "" }, actor: nil)

    assert result.ok?, result.errors.to_sentence
    assert user.reload.authenticate("password")
  end

  test "a password with a matching confirmation is changed" do
    user = users(:one)
    result = Users::Save.call(user, attributes: { password: "new-password-1", password_confirmation: "new-password-1" }, actor: nil)

    assert result.ok?, result.errors.to_sentence
    assert user.reload.authenticate("new-password-1")
  end

  # Final fix wave (C, P17): `has_secure_password` only compares the
  # confirmation when it's non-nil, and a form that omits it (or a caller
  # that forgets it) would otherwise set the password unconfirmed.
  test "a password without a confirmation is refused" do
    user = users(:one)
    [ { password: "new-password-1" }, { password: "new-password-1", password_confirmation: "" } ].each do |attributes|
      result = Users::Save.call(user, attributes: attributes, actor: nil)

      assert_not result.ok?
      assert_includes result.errors, "Password confirmation can't be blank"
      assert user.reload.authenticate("password")
    end
  end

  test "a new user needs a confirmation too" do
    result = Users::Save.call(attributes: { email_address: "fresh@example.com", password: "new-password-1" }, actor: nil)

    assert_not result.ok?
    assert_not User.exists?(email_address: "fresh@example.com")
  end

  # --- Groups and owner (access-control design spec §3.3 "Users", Task 8) ------

  test "a user's groups are saved and recorded in user.updated" do
    user = users(:reader)
    groups = [ access_control_groups(:author), access_control_groups(:read_only) ]

    result = as_owner { Users::Save.call(user, attributes: { group_ids: [ "", *groups.map(&:id) ] }) }

    assert result.ok?, result.errors.inspect
    assert_equal groups.map(&:id).sort, user.reload.group_ids.sort
    event = Audit::Event.find_by!(action: "user.updated", subject: user)
    assert_equal [ [ access_control_groups(:read_only).id ], groups.map(&:id).sort ], event.field_changes["group_ids"]
    assert_equal groups.map(&:id).sort, event.snapshot["group_ids"]
  end

  test "a non-owner can't add someone to a group holding permissions they lack" do
    managers = AccessControl::Group.create!(name: "User managers")
    AccessControl::Grant.create!(group: managers, permission: "users.manage", scope: {})
    # Enough to manage the reader at all (their Read only group, fix round 1 I1).
    AccessControl::Grant.create!(group: managers, permission: "posts.read", scope: {})
    AccessControl::Grant.create!(group: managers, permission: "pages.read", scope: {})
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)

    result = as(users(:editor_branch)) do
      Users::Save.call(users(:reader), attributes: { group_ids: [ access_control_groups(:admin).id ] })
    end

    assert result.denied?
    assert_equal [ "You don't have permission to add users to the Admin group" ], result.errors
    assert_equal [ access_control_groups(:read_only).id ], users(:reader).reload.group_ids
  end

  test "only an owner may change owner" do
    result = as(users(:two)) { Users::Save.call(users(:reader), attributes: { owner: "1" }) }
    assert result.denied?
    assert_equal [ "Only an owner can change who is an owner" ], result.errors
    assert_not users(:reader).reload.owner?

    # An unchanged value (the form's hidden "0") isn't a change.
    assert as(users(:two)) { Users::Save.call(users(:reader), attributes: { owner: "0", email_address: "r@example.com" }) }.ok?
  end

  test "an owner promotes a user, recorded as user.owner_changed" do
    result = as_owner { Users::Save.call(users(:reader), attributes: { owner: "1" }) }

    assert result.ok?, result.errors.inspect
    assert users(:reader).reload.owner?
    event = Audit::Event.find_by!(action: "user.owner_changed", subject: users(:reader))
    assert_equal({ "owner" => [ false, true ] }, event.field_changes)
    assert_not Audit::Event.exists?(action: "user.updated", subject: users(:reader))
  end

  test "the last owner can't be demoted" do
    result = as_owner { Users::Save.call(users(:one), attributes: { owner: "0" }) }

    assert_not result.ok?
    assert_includes result.errors.to_sentence, "can't demote the last owner"
    assert users(:one).reload.owner?
  end
end
