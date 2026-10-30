require "test_helper"

# An invitation is not a user (spec "Invites", the owner's choice of
# 2026-10-30): a row of its own whose link's token is signed over `sent_at`
# and the address (plan Ruling 3, ruling F1), so a resend or a changed
# address kills the old link, a withdrawal (the row deleted) finds nothing,
# and an accepted invitation still finds its row, which says it is used.
class InvitationTest < ActiveSupport::TestCase
  test "a link works for 7 days and dies on resend and on withdrawal; an accepted one still finds its row, used" do
    invitation = open_invitation("dana@example.com")
    token = invitation.generate_token_for(:accept)

    assert_equal invitation, Invitation.find_by_token_for(:accept, token)
    assert_equal invitation.sent_at + 7.days, invitation.expires_at
    # In seconds: `travel(7.days)` adds calendar days in the machine's zone,
    # which across a change of clocks is an hour more or less than the
    # token's 168 hours.
    valid_for = Invitation::VALID_FOR.to_i.seconds
    travel(valid_for - 1.minute) { assert_equal invitation, Invitation.find_by_token_for(:accept, token) }
    travel(valid_for + 1.minute) do
      assert_nil Invitation.find_by_token_for(:accept, token)
      assert invitation.expired?
    end

    travel(1.second) { invitation.update!(sent_at: Time.current) }
    assert_nil Invitation.find_by_token_for(:accept, token)
    resent = invitation.generate_token_for(:accept)
    assert_equal invitation, Invitation.find_by_token_for(:accept, resent)

    invitation.update!(accepted_at: Time.current)
    used = Invitation.find_by_token_for(:accept, resent)
    assert_equal invitation, used
    assert used.used?

    other = open_invitation("eli@example.com")
    withdrawn = other.generate_token_for(:accept)
    other.destroy!
    assert_nil Invitation.find_by_token_for(:accept, withdrawn)
    assert_nil Invitation.find_by_token_for(:accept, "junk")
  end

  # Ruling F1, now on the invitation: a link mailed to a wrong address must
  # not work once the address is another.
  test "a link dies when the invitation's address is changed" do
    invitation = open_invitation("dnaa@example.com")
    token = invitation.generate_token_for(:accept)

    invitation.update!(email_address: "dana@example.com")
    assert_nil Invitation.find_by_token_for(:accept, token)
    assert_equal invitation, Invitation.find_by_token_for(:accept, invitation.generate_token_for(:accept))
  end

  test "the address is normalised as a user's, one open invitation per address, and any number of accepted ones" do
    invitation = open_invitation(" Dana@Example.com ")
    assert_equal "dana@example.com", invitation.email_address
    assert_raises(ActiveRecord::RecordNotUnique) { open_invitation("dana@example.com") }

    invitation.update!(accepted_at: Time.current)
    again = open_invitation("dana@example.com")
    assert_equal [ again ], Invitation.open.where(email_address: "dana@example.com").to_a
    assert_equal [ invitation ], Invitation.accepted.to_a
  end

  test "used means accepted, or an account has the address by now" do
    invitation = open_invitation("dana@example.com")
    assert_not invitation.used?

    User.create!(email_address: "dana@example.com", password: "a-long-password-1")
    assert invitation.used?
  end

  test "its groups are join rows: a deleted group drops out, a withdrawn invitation takes its rows, and nobody is a member" do
    group = AccessControl::Group.create!(name: "Temporary")
    invitation = open_invitation("dana@example.com", groups: [ group, access_control_groups(:editor) ])
    assert_equal [ access_control_groups(:editor), group ].sort_by(&:id), invitation.groups.sort_by(&:id)
    assert_empty access_control_groups(:editor).users.where(email_address: "dana@example.com")

    group.destroy!
    assert_equal [ access_control_groups(:editor) ], invitation.reload.groups.to_a

    invitation.destroy!
    assert_empty InvitationGroup.where(invitation_id: invitation.id)
  end

  test "an inviter or an account that is deleted is nulled, and the invitation stays" do
    inviter = User.create!(email_address: "inviter@example.com", password: "a-long-password-1")
    invitation = open_invitation("dana@example.com", inviter: inviter)
    account = User.create!(email_address: "dana@example.com", password: "a-long-password-1")
    invitation.update!(accepted_at: Time.current, user: account)

    inviter.destroy!
    account.destroy!

    invitation.reload
    assert_nil invitation.inviter_id
    assert_nil invitation.user_id
  end
end
