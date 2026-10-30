require "test_helper"

# `Invitations::Invite` (spec "Invites", design answer M4): an invitation --
# no user -- in its groups, and a mail with the link, sent only while mail
# works.
class Invitations::InviteTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  SITE = "https://cms.example.test".freeze

  def invite(as_user: users(:one), **options)
    as(as_user) { Invitations::Invite.call(**{ email_address: "dana@example.com" }.merge(options)) }
  end

  # The token as the mail carries it: the link's fragment.
  def token_in(mail) = mail.text_part.body.to_s[%r{/cs-studio/invitation#([^\s"]+)}, 1]

  test "an owner invites: an invitation and no user, its groups, one event that names it, and a mail with a working link" do
    mail = nil
    with_mail_state(:working) do
      with_site_address(SITE) do
        result = nil
        assert_no_difference [ -> { User.count }, -> { AccessControl::Membership.count } ] do
          assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
            perform_enqueued_jobs do
              result = invite(name: "Dana", group_ids: [ access_control_groups(:read_only).id ])
              assert result.ok?, result.errors.inspect
            end
          end
        end
        mail = ActionMailer::Base.deliveries.last

        invitation = result.record.reload
        assert invitation.open?
        assert_equal [ "dana@example.com", "Dana", users(:one) ], [ invitation.email_address, invitation.name, invitation.inviter ]
        assert_in_delta Time.current, invitation.sent_at, 5
        assert_equal [ access_control_groups(:read_only) ], invitation.groups.to_a

        assert_equal [ "dana@example.com" ], mail.to
        assert_equal invitation, Invitation.find_by_token_for(:accept, token_in(mail))

        event = Audit::Event.find_by!(action: "invitation.created")
        assert_equal [ invitation, users(:one).id, "dana@example.com" ], [ event.subject, event.user_id, event.subject_label ]
        assert_empty event.metadata
        assert_equal [ access_control_groups(:read_only).id ], event.snapshot["group_ids"]
        assert_equal [ [], [ access_control_groups(:read_only).id ] ], event.field_changes["group_ids"]
      end
    end

    # The token is made by the mailer in the job, never an argument of it.
    assert_not_includes performed_jobs.map { |job| job["arguments"] }.to_json, token_in(mail)
    assert_not_includes Audit::Event.pluck(:snapshot, :field_changes, :metadata).to_json, token_in(mail)
  end

  test "a denied actor gets the service's 403 and writes nothing" do
    with_mail_state(:working) do
      assert_no_difference -> { Invitation.count } do
        result = invite(as_user: users(:author))
        assert result.denied?
        assert_equal [ "You don't have permission to manage users" ], result.errors
      end
      assert_no_enqueued_jobs
      assert_equal [ "access.denied" ], Audit::Event.pluck(:action)
      assert_equal "Invitation", Audit::Event.sole.metadata["subject_type"]
    end
  end

  # Review Focus 4: the typed address is normalised as an account's is
  # before it is compared, so the sentence is the account's, not a 500.
  test "an address in another case or with spaces that has an account is refused with its sentence" do
    with_mail_state(:working) do
      result = invite(email_address: " Reader@Example.com ")

      assert_not result.ok?
      assert_equal [ "Someone with this address already has an account." ], result.errors
      assert_equal [ "Someone with this address already has an account." ], result.record.errors[:email_address]
      assert_equal 0, Invitation.count
      assert_no_enqueued_jobs
      assert_empty Audit::Event.where(action: "invitation.created")
    end
  end

  test "an address with an open invitation is refused with its sentence and the invitation is left as it was; an accepted one is no obstacle" do
    open = open_invitation("dana@example.com", sent_at: 1.day.ago)

    with_mail_state(:working) do
      result = invite(email_address: "DANA@example.com")

      assert_equal [ "This address is already invited." ], result.errors
      assert_equal open.sent_at, open.reload.sent_at
      assert_no_enqueued_jobs

      # Accepted, and the account deleted since: the address may be invited again.
      open.update!(accepted_at: Time.current)
      assert invite(email_address: "dana@example.com").ok?
      assert_equal 1, Invitation.open.where(email_address: "dana@example.com").count
    end
  end

  test "an invitation is refused while mail is not ready" do
    # The suite's default: saved, not tested.
    assert_not MailSettings.current.ready?

    result = invite

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "Invites need mail." ], result.errors
    assert_equal 0, Invitation.count
    assert_no_enqueued_jobs
  end

  test "a blank address is the model's own error" do
    with_mail_state(:working) do
      result = invite(email_address: "  ")

      assert_includes result.errors, "Email address can't be blank"
      assert_no_enqueued_jobs
    end
  end

  # As `Users::Save`: accepting puts the person into the groups, which hands
  # them their grants, so a non-owner may only invite into groups they could
  # assign.
  test "a user manager may not invite into a group that would give more than they have" do
    managers = AccessControl::Group.create!(name: "User managers")
    AccessControl::Grant.create!(group: managers, permission: "users.manage", scope: {})
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)

    with_mail_state(:working) do
      refused = invite(as_user: users(:editor_branch), group_ids: [ access_control_groups(:admin).id ])
      assert refused.denied?
      assert_equal [ "You don't have permission to add users to the Admin group" ], refused.errors
      assert_equal 0, Invitation.count

      assert invite(as_user: users(:editor_branch)).ok?
    end
  end

  # The mail is queued once the invitation is committed: inside a caller's
  # transaction it waits for that commit, and a rollback sends nothing.
  test "inside an outer transaction the mail is queued only after it commits, and not at all if it rolls back" do
    with_mail_state(:working) do
      Invitation.transaction(requires_new: true) do
        assert invite(email_address: "rolled@example.com").ok?
        assert_no_enqueued_jobs
        raise ActiveRecord::Rollback
      end
      assert_no_enqueued_jobs
      assert_nil Invitation.find_by(email_address: "rolled@example.com")

      Invitation.transaction(requires_new: true) do
        assert invite(email_address: "kept@example.com").ok?
        assert_no_enqueued_jobs
      end
      assert_enqueued_jobs 1, only: MailDeliveryJob
    end
  end
end
