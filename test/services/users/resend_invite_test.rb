require "test_helper"

# `Users::ResendInvite` (design answer M4, "Resend invite"): a new link, seven
# more days, and the old link dead.
class Users::ResendInviteTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { @invited = invited_user("dana@example.com", sent_at: 2.days.ago) }

  def resend(user = @invited, as_user: users(:one)) = as(as_user) { Users::ResendInvite.call(user) }

  test "a resend moves the link's date, kills the old link, sends a new one and is recorded" do
    old_token = @invited.generate_token_for(:invite)

    with_mail_state(:working) do
      with_site_address("https://cms.example.test") do
        assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
          perform_enqueued_jobs { assert resend.ok? }
        end
      end
    end

    assert_in_delta Time.current, @invited.reload.invite_sent_at, 5
    assert @invited.invited?
    assert_nil User.find_by_token_for(:invite, old_token)
    assert_equal [ "dana@example.com" ], ActionMailer::Base.deliveries.last.to
    event = Audit::Event.find_by!(action: "user.invite_resent")
    assert_equal [ @invited, users(:one).id ], [ event.subject, event.user_id ]
    assert_empty event.metadata
  end

  test "a denied actor gets the service's 403 and writes nothing" do
    with_mail_state(:working) do
      result = resend(as_user: users(:author))

      assert result.denied?
      assert_equal [ "You don't have permission to manage users" ], result.errors
      assert_equal @invited.invite_sent_at, @invited.reload.invite_sent_at
      assert_no_enqueued_jobs
      assert_equal [ "access.denied" ], Audit::Event.pluck(:action)
    end
  end

  test "someone who is not invited gets no invite, and a resend is refused while mail is not ready" do
    with_mail_state(:working) do
      result = resend(users(:reader))
      assert_equal [ "There is no open invite for this person." ], result.errors
      assert_no_enqueued_jobs
    end

    result = resend
    assert_equal [ "Invites need mail." ], result.errors
    assert_no_enqueued_jobs
    assert_empty Audit::Event.where(action: "user.invite_resent")
  end
end
