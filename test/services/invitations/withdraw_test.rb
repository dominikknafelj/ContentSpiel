require "test_helper"

# `Invitations::Withdraw` (design answer M4, "Withdraw invite"): the
# invitation is deleted, its groups and its link with it.
class Invitations::WithdrawTest < ActiveSupport::TestCase
  setup { @invitation = open_invitation("dana@example.com", groups: [ access_control_groups(:read_only) ]) }

  def withdraw(invitation = @invitation, as_user: users(:one)) = as(as_user) { Invitations::Withdraw.call(invitation) }

  test "a withdrawal deletes the invitation and its groups, kills the link and is recorded" do
    token = @invitation.generate_token_for(:accept)

    assert_no_difference -> { User.count } do
      assert withdraw.ok?
    end

    assert_nil Invitation.find_by(id: @invitation.id)
    assert_empty InvitationGroup.where(invitation_id: @invitation.id)
    assert_nil Invitation.find_by_token_for(:accept, token)
    event = Audit::Event.find_by!(action: "invitation.withdrawn")
    assert_equal [ "Invitation", @invitation.id, users(:one).id ], [ event.subject_type, event.subject_id, event.user_id ]
    assert_equal "dana@example.com", event.subject_label
    assert_empty event.metadata
  end

  test "a denied actor gets the service's 403 and writes nothing" do
    result = withdraw(as_user: users(:author))

    assert result.denied?
    assert_equal [ "You don't have permission to manage users" ], result.errors
    assert Invitation.exists?(@invitation.id)
    assert_equal [ "access.denied" ], Audit::Event.pluck(:action)
  end

  # An accepted invitation is history: its account is the person's own, and
  # deleting that is `Users::Destroy`.
  test "an accepted invitation is not withdrawn" do
    @invitation.update!(accepted_at: Time.current)
    result = withdraw

    assert_equal [ "There is no open invite for this person." ], result.errors
    assert Invitation.exists?(@invitation.id)
    assert_empty Audit::Event.where(action: "invitation.withdrawn")
  end

  test "a user manager may not withdraw an invitation into a group that outranks them" do
    managers = AccessControl::Group.create!(name: "User managers")
    AccessControl::Grant.create!(group: managers, permission: "users.manage", scope: {})
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)
    into_admin = open_invitation("eli@example.com", groups: [ access_control_groups(:admin) ])

    assert withdraw(into_admin, as_user: users(:editor_branch)).denied?
    assert Invitation.exists?(into_admin.id)
  end
end
