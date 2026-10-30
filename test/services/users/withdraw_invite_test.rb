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

  # `User#other_owner_remains?` counts the OTHER owners who can sign in, so
  # an invited row made an owner by hand is not stuck while a real owner
  # remains; and a destroy the model refuses is answered with its own
  # sentence, not "no open invite".
  test "an invited row made an owner by hand is withdrawn, and a refused destroy says why" do
    @invited.update_columns(owner: true)
    assert withdraw(@invited.reload).ok?
    assert_nil User.find_by(id: @invited.id)

    # With no real owner left besides it (a state no screen makes), the model
    # refuses, and the answer is the model's.
    stuck = invited_user("eli@example.com")
    stuck.update_columns(owner: true)
    users(:one).update_columns(owner: false)
    result = as(nil, channel: :console) { Users::WithdrawInvite.call(stuck.reload) }
    assert_equal [ "The last owner can't be deleted" ], result.errors
    assert User.exists?(stuck.id)
    assert_empty Audit::Event.where(action: "user.invite_withdrawn", subject_id: stuck.id)
  end
end
