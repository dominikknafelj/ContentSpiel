require "test_helper"

# `Users::WithdrawInvite` (design answer M4, "Withdraw invite"): the invited
# row is deleted, and the link with it.
class Users::WithdrawInviteTest < ActiveSupport::TestCase
  setup { @invited = invited_user("dana@example.com", groups: [ access_control_groups(:read_only) ]) }

  def withdraw(user = @invited, as_user: users(:one)) = as(as_user) { Users::WithdrawInvite.call(user) }

  test "a withdrawal deletes the row and its memberships, kills the link and is recorded" do
    token = @invited.generate_token_for(:invite)

    assert withdraw.ok?

    assert_nil User.find_by(id: @invited.id)
    assert_empty AccessControl::Membership.where(user_id: @invited.id)
    assert_nil User.find_by_token_for(:invite, token)
    event = Audit::Event.find_by!(action: "user.invite_withdrawn")
    assert_equal [ "User", @invited.id, users(:one).id ], [ event.subject_type, event.subject_id, event.user_id ]
    assert_equal "dana@example.com", event.subject_label
    assert_empty event.metadata
  end

  test "a denied actor gets the service's 403 and writes nothing" do
    result = withdraw(as_user: users(:author))

    assert result.denied?
    assert_equal [ "You don't have permission to manage users" ], result.errors
    assert User.exists?(@invited.id)
    assert_equal [ "access.denied" ], Audit::Event.pluck(:action)
  end

  # A withdrawal is no way to delete an account: that is `Users::Destroy`,
  # with its owner rules and the tokens it revokes.
  test "someone who is not invited is not withdrawn" do
    result = withdraw(users(:reader))

    assert_equal [ "There is no open invite for this person." ], result.errors
    assert User.exists?(users(:reader).id)
    assert_empty Audit::Event.where(action: "user.invite_withdrawn")
  end
end
