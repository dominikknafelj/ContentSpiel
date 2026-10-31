require "test_helper"

# `Invitations::Accounts`: an account made for an invited address closes
# that address's open invitation, heard from the audit log's after-commit
# notification, so the users side knows nothing of it.
class Invitations::AccountsTest < ActiveSupport::TestCase
  def make_user(email) = as(users(:one)) { Users::Save.call(User.new, attributes: { email_address: email, password: "a-long-password-1", password_confirmation: "a-long-password-1" }) }

  test "an account made for an invited address deletes its open invitation, and leaves the others" do
    open = open_invitation("dana@example.com", groups: [ access_control_groups(:editor) ])
    other = open_invitation("eli@example.com")

    assert make_user("Dana@Example.com").ok?

    assert_not Invitation.exists?(open.id)
    assert_empty InvitationGroup.where(invitation_id: open.id)
    assert Invitation.exists?(other.id)
  end

  test "an account moved onto an invited address closes it too; another edit closes nothing" do
    invitation = open_invitation("dana@example.com")
    user = users(:reader)

    assert as(users(:one)) { Users::Save.call(user, attributes: { name: "Renamed" }) }.ok?
    assert Invitation.exists?(invitation.id)

    assert as(users(:one)) { Users::Save.call(user.reload, attributes: { email_address: "dana@example.com" }) }.ok?
    assert_not Invitation.exists?(invitation.id)
  end

  test "an accepted invitation is kept: its link still says used" do
    accepted = open_invitation("dana@example.com").tap { |invitation| invitation.update!(accepted_at: Time.current) }
    assert make_user("dana@example.com").ok?
    assert Invitation.exists?(accepted.id)
  end

  # It runs after the user's write has committed, in the same request: a
  # failure must never become the save's.
  test "a listener that fails never raises into the user's save, and is reported" do
    open_invitation("dana@example.com")
    reported = []

    with_singleton_override(Invitation, :open, -> { raise ActiveRecord::StatementInvalid, "boom" }) do
      with_singleton_override(Rails.error, :report, ->(error, **) { reported << error }) do
        result = nil
        assert_nothing_raised { result = make_user("dana@example.com") }
        assert result.ok?
      end
    end

    assert User.exists?(email_address: "dana@example.com")
    assert_equal [ ActiveRecord::StatementInvalid ], reported.map(&:class)
  end
end
