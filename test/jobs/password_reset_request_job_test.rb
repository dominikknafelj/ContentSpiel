require "test_helper"

# The reset request's job: it finds the account the request did not look
# up, and queues the reset mail for it as the request once did.
class PasswordResetRequestJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper
  include LogCapture

  setup do
    @user = users(:one)
    # Integration and job tests clear no deliveries of their own.
    ActionMailer::Base.deliveries.clear
    put_mail_state(:working)
  end

  def queued = { fingerprint: MailSettings.current.fingerprint }

  test "the job queues the reset mail for an account and nothing for an unknown address, logging no address" do
    log = capture_log do
      assert_enqueued_email_with PasswordsMailer, :reset, params: queued, args: [ @user ] do
        PasswordResetRequestJob.perform_now(" #{@user.email_address.upcase} ")
      end
      assert_no_enqueued_emails do
        [ "nobody@example.org", "", "ann\0@example.org" ].each { PasswordResetRequestJob.perform_now(it) }
      end
      PasswordResetRequestJob.perform_later(@user.email_address)
      perform_enqueued_jobs(only: PasswordResetRequestJob)
    end

    assert_includes log, "PasswordResetRequestJob", "the job's own lines are in the capture"
    assert_not_includes log, @user.email_address
    assert_not_includes log, "nobody@example.org"
  end

  test "with mail not ready when it runs the job sends nothing and logs nothing of the address" do
    %i[ not_set_up untested ].each do |state|
      with_mail_state(state) do
        log = capture_log do
          assert_no_enqueued_emails { PasswordResetRequestJob.perform_now(@user.email_address) }
        end
        assert_not_includes log, @user.email_address
      end
    end
  end

  test "the origin reaches the mail as before" do
    with_site_address(nil) do
      assert_enqueued_email_with PasswordsMailer, :reset, params: queued, args: [ @user, { origin: "http://localhost:3000" } ] do
        PasswordResetRequestJob.perform_now(@user.email_address, origin: "http://localhost:3000")
      end

      perform_enqueued_jobs
      assert_includes ActionMailer::Base.deliveries.sole.text_part.body.to_s, "http://localhost:3000/cs-studio/password/edit#"
    end
  end

  SSO_OFF = "[ContentSpiel] A reset was asked for an account linked to single sign-on, which is off.".freeze

  test "a reset asked for a linked account sends the reminder with no reset link" do
    linked = link_to_sso(users(:reader))

    with_sso do
      with_site_address(nil) do
        assert_enqueued_email_with PasswordsMailer, :sso_reminder, params: queued, args: [ linked, { provider: OidcHelper::NAME, origin: "http://localhost:3000" } ] do
          PasswordResetRequestJob.perform_now(linked.email_address, origin: "http://localhost:3000")
        end
        perform_enqueued_jobs
      end
    end

    mail = ActionMailer::Base.deliveries.sole
    assert_equal [ linked.email_address ], mail.to
    assert_includes mail.text_part.body.to_s, "http://localhost:3000/cs-studio/sign-in"
    assert_not_includes mail.encoded, "/password/edit"
  end

  test "under SSO_REQUIRED a non-owner's reset sends the reminder, and an owner's the reset" do
    with_sso(required: true) do
      assert_enqueued_email_with PasswordsMailer, :sso_reminder, params: queued, args: [ users(:reader), { provider: OidcHelper::NAME } ] do
        PasswordResetRequestJob.perform_now(users(:reader).email_address)
      end
      assert_enqueued_email_with PasswordsMailer, :reset, params: queued, args: [ @user ] do
        PasswordResetRequestJob.perform_now(@user.email_address)
      end
    end
  end

  test "with SSO off a linked account's reset sends nothing and the line names nobody" do
    link_to_sso(users(:reader))

    log = capture_log do
      assert_no_enqueued_emails { PasswordResetRequestJob.perform_now(users(:reader).email_address) }
    end

    assert_equal [ SSO_OFF ], log.lines.map(&:strip).grep(/ContentSpiel/)
    assert_not_includes log, users(:reader).email_address
    assert_not_includes log, "id=#{users(:reader).id}"
  end
end
