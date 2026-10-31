require "test_helper"

# `Invitations::Resend` (design answer M4, "Resend invite"): a new link, seven
# more days, and the old link dead.
class Invitations::ResendTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { @invitation = open_invitation("dana@example.com", sent_at: 2.days.ago) }

  def resend(invitation = @invitation, as_user: users(:one)) = as(as_user) { Invitations::Resend.call(invitation) }

  test "a resend moves the link's date, kills the old link, sends a new one and is recorded" do
    old_token = @invitation.generate_token_for(:accept)

    with_mail_state(:working) do
      with_site_address("https://cms.example.test") do
        assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
          perform_enqueued_jobs { assert resend.ok? }
        end
      end
    end

    assert_in_delta Time.current, @invitation.reload.sent_at, 5
    assert @invitation.open?
    assert_nil Invitation.find_by_token_for(:accept, old_token)
    assert_equal [ "dana@example.com" ], ActionMailer::Base.deliveries.last.to
    event = Audit::Event.find_by!(action: "invitation.resent")
    assert_equal [ @invitation, users(:one).id ], [ event.subject, event.user_id ]
    assert_equal [ "sent_at" ], event.field_changes.keys - %w[updated_at]
    assert_empty event.metadata
  end

  test "a denied actor gets the service's 403 and writes nothing" do
    with_mail_state(:working) do
      result = resend(as_user: users(:author))

      assert result.denied?
      assert_equal [ "You don't have permission to manage users" ], result.errors
      assert_equal @invitation.sent_at, @invitation.reload.sent_at
      assert_no_enqueued_jobs
      assert_equal [ "access.denied" ], Audit::Event.pluck(:action)
    end
  end

  test "an accepted invitation gets no new link, and a resend is refused while mail is not ready" do
    accepted = open_invitation("eli@example.com").tap { |invitation| invitation.update!(accepted_at: Time.current) }
    with_mail_state(:working) do
      result = resend(accepted)
      assert_equal [ "There is no open invite for this person." ], result.errors
      assert_no_enqueued_jobs
    end

    result = resend
    assert_equal [ "Invites need mail." ], result.errors
    assert_no_enqueued_jobs
    assert_empty Audit::Event.where(action: "invitation.resent")
  end

  # As a user's: a non-owner may not act on an invitation into a group they
  # could not manage.
  test "a user manager may not resend an invitation into a group that outranks them" do
    managers = AccessControl::Group.create!(name: "User managers")
    AccessControl::Grant.create!(group: managers, permission: "users.manage", scope: {})
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)
    into_admin = open_invitation("eli@example.com", groups: [ access_control_groups(:admin) ])

    with_mail_state(:working) do
      assert resend(into_admin, as_user: users(:editor_branch)).denied?
      assert resend(as_user: users(:editor_branch)).ok?
    end
  end
end
