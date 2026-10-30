require "test_helper"

# `Users::Invite` (spec "Invites", design answer M4): a row that cannot sign
# in until the person sets a password, and a mail with the link, sent only
# while mail works.
class Users::InviteTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  SITE = "https://cms.example.test".freeze

  def invite(as_user: users(:one), **options)
    as(as_user) { Users::Invite.call(**{ email_address: "dana@example.com" }.merge(options)) }
  end

  # The token as the mail carries it: the link's fragment.
  def token_in(mail) = mail.text_part.body.to_s[%r{/cs-studio/invitation#([^\s"]+)}, 1]

  test "an owner invites: a row that cannot sign in, in its groups, one event that names no one beyond its subject, and a mail with a working link" do
    mail = nil
    with_mail_state(:working) do
      with_site_address(SITE) do
        result = nil
        assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
          perform_enqueued_jobs do
            result = invite(name: "Dana", group_ids: [ access_control_groups(:read_only).id ])
            assert result.ok?, result.errors.inspect
          end
        end
        mail = ActionMailer::Base.deliveries.last

        user = result.record.reload
        assert user.invited?
        assert_equal [ "dana@example.com", "Dana", users(:one) ], [ user.email_address, user.name, user.invited_by ]
        assert_in_delta Time.current, user.invite_sent_at, 5
        assert_not_includes User.can_sign_in, user
        assert_equal [ access_control_groups(:read_only) ], user.groups.to_a

        assert_equal [ "dana@example.com" ], mail.to
        assert_equal user, User.find_by_token_for(:invite, token_in(mail))

        event = Audit::Event.find_by!(action: "user.invited")
        assert_equal [ user, users(:one).id ], [ event.subject, event.user_id ]
        assert_empty event.metadata
        assert_equal [ access_control_groups(:read_only).id ], event.snapshot["group_ids"]
        assert_not_includes event.attributes.to_json, "password"
      end
    end

    # The token is made by the mailer in the job, never an argument of it.
    assert_not_includes performed_jobs.map { |job| job["arguments"] }.to_json, token_in(mail)
  end

  test "a denied actor gets the service's 403 and writes nothing" do
    with_mail_state(:working) do
      assert_no_difference -> { User.count } do
        result = invite(as_user: users(:author))
        assert result.denied?
        assert_equal [ "You don't have permission to manage users" ], result.errors
      end
      assert_no_enqueued_jobs
      assert_equal [ "access.denied" ], Audit::Event.pluck(:action)
    end
  end

  # Review Focus 4: `normalizes` strips and lower-cases the typed address
  # before it is compared, so the sentence is the account's, not a 500 or a
  # second row.
  test "an address in another case or with spaces that has an account is refused with its sentence" do
    with_mail_state(:working) do
      result = invite(email_address: " Reader@Example.com ")

      assert_not result.ok?
      assert_equal [ "Someone with this address already has an account." ], result.errors
      assert_equal [ "Someone with this address already has an account." ], result.record.errors[:email_address]
      assert_equal 1, User.where(email_address: "reader@example.com").count
      assert_no_enqueued_jobs
      assert_empty Audit::Event.where(action: "user.invited")
    end
  end

  test "an address already invited is refused with its sentence, and the invite is left as it was" do
    invited = invited_user("dana@example.com", sent_at: 1.day.ago)

    with_mail_state(:working) do
      result = invite(email_address: "DANA@example.com")

      assert_equal [ "This address is already invited." ], result.errors
      assert_equal invited.invite_sent_at, invited.reload.invite_sent_at
      assert_no_enqueued_jobs
    end
  end

  test "an invite is refused while mail is not ready" do
    # The suite's default: saved, not tested.
    assert_not MailSettings.current.ready?

    result = invite

    assert_not result.ok?
    assert_not result.denied?
    assert_equal [ "Invites need mail." ], result.errors
    assert_nil User.find_by(email_address: "dana@example.com")
    assert_no_enqueued_jobs
  end

  test "a blank address is the model's own error" do
    with_mail_state(:working) do
      result = invite(email_address: "  ")

      assert_includes result.errors, "Email address can't be blank"
      assert_no_enqueued_jobs
    end
  end

  # As `Users::Save`: adding someone to a group hands them its grants, so a
  # non-owner may only invite into groups they could assign.
  test "a user manager may not invite into a group that would give more than they have" do
    managers = AccessControl::Group.create!(name: "User managers")
    AccessControl::Grant.create!(group: managers, permission: "users.manage", scope: {})
    AccessControl::Membership.create!(user: users(:editor_branch), group: managers)

    with_mail_state(:working) do
      refused = invite(as_user: users(:editor_branch), group_ids: [ access_control_groups(:admin).id ])
      assert refused.denied?
      assert_equal [ "You don't have permission to add users to the Admin group" ], refused.errors
      assert_nil User.find_by(email_address: "dana@example.com")

      assert invite(as_user: users(:editor_branch)).ok?
    end
  end
end
