require "test_helper"

# The lock-out mail's job: it finds the account the request did not look
# up, and mails it only when there is one and mail is ready.
class SignIn::LockoutMailJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper
  include LogCapture

  SITE = "https://docs.example.org".freeze

  setup do
    freeze_time
    @user = users(:one)
  end

  def perform(email, **)
    SignIn::LockoutMailJob.perform_now(email, locked_at: Time.current, from_address: "203.0.113.7", minutes: 1, **)
  end

  test "the job mails the account through ApplicationMailer.queue when mail is ready" do
    with_mail_state(:working) do
      fingerprint = MailSettings.current.fingerprint
      assert_enqueued_email_with SignInMailer, :locked, params: { fingerprint: fingerprint },
        args: [ @user, { locked_at: Time.current, from_address: "203.0.113.7", minutes: 1, origin: "http://localhost:3000" } ] do
        perform(" #{@user.email_address.upcase} ", origin: "http://localhost:3000")
      end

      with_site_address(SITE) do
        assert_emails(1) { perform_enqueued_jobs }
      end
      assert_equal [ @user.email_address ], ActionMailer::Base.deliveries.sole.to
    end
  end

  test "for an address with no account, or with mail not ready, it sends nothing and logs no address" do
    log = capture_log do
      with_mail_state(:working) do
        assert_no_enqueued_emails { perform("nobody@example.org") }
        assert_no_enqueued_emails { perform("") }
      end
      with_mail_state(:untested) do
        assert_no_enqueued_emails { perform(@user.email_address) }
      end
    end

    assert_not_includes log, "nobody@example.org"
    assert_not_includes log, @user.email_address
  end

  test "the job's arguments are not logged" do
    with_mail_state(:working) do
      log = capture_log do
        SignIn::LockoutMailJob.perform_later(@user.email_address, locked_at: Time.current, from_address: "203.0.113.7", minutes: 1)
        perform_enqueued_jobs(only: SignIn::LockoutMailJob)
      end

      assert_includes log, "SignIn::LockoutMailJob", "the job's own lines are in the capture"
      assert_enqueued_jobs 1, only: MailDeliveryJob
      assert_not_includes log, @user.email_address
    end
  end
end
