require "test_helper"

# The reset request's job: it finds the account the request did not look
# up, and queues the reset mail for it as the request once did.
class PasswordResetRequestJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper
  include LogCapture

  setup do
    @user = users(:one)
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

  test "the origin reaches the mail as before" do
    with_site_address(nil) do
      assert_enqueued_email_with PasswordsMailer, :reset, params: queued, args: [ @user, { origin: "http://localhost:3000" } ] do
        PasswordResetRequestJob.perform_now(@user.email_address, origin: "http://localhost:3000")
      end

      perform_enqueued_jobs
      assert_includes ActionMailer::Base.deliveries.sole.text_part.body.to_s, "http://localhost:3000/cs-studio/password/edit#"
    end
  end
end
