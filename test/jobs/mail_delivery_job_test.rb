require "test_helper"

# The job every mail is delivered by (spec, decision 5): a connection failure
# is retried three times with backoff and recorded after the last; a refused
# login, a refused sender and anything else are recorded at once and not
# retried; a success is recorded with the fingerprint the mail was queued
# under, which verifies the settings only when it is still the current one.
class MailDeliveryJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper
  include LogCapture

  USERNAME = "job-login@example.test".freeze
  PASSWORD = "job-Pa55-w0rd".freeze

  setup { @user = users(:one) }

  class BrokenMailer < ApplicationMailer
    def broken(to)
      mail(to: to, subject: "Broken") { |format| format.text { raise NoMethodError, "undefined method 'title' for nil" } }
    end
  end

  def queue_reset
    ApplicationMailer.queue(PasswordsMailer, :reset, @user, origin: "http://localhost:3000")
  end

  def stub_settings(port)
    { mail_server: SmtpStub::HOST, mail_port: port, mail_security: "starttls",
      mail_username: USERNAME, mail_password: PASSWORD, mail_sender_address: "no-reply@example.test" }
  end

  def site = SiteSetting.instance.reload

  # The state as the row says it now. A job performed inline runs under its
  # own `Current` and writes its own copy of the row: the test's
  # `Current.site`, loaded when the mail was queued, does not see it.
  def state = MailSettings.current(site).state

  # How many times the job ran, and how many performs had happened each time
  # a failure was recorded.
  def count_attempts
    performs = 0
    recorded = []
    counting = ->(event) { performs += 1 if event.payload[:job].is_a?(MailDeliveryJob) }
    record = MailSettings.method(:record_failure!)
    ActiveSupport::Notifications.subscribed(counting, "perform_start.active_job") do
      with_singleton_override(MailSettings, :record_failure!, ->(**args) { recorded << performs; record.call(**args) }) do
        yield
      end
    end
    [ performs, recorded ]
  end

  test "a connection failure is retried three times and recorded once, after the last" do
    with_site_address(nil) do
      with_mail_state(:working, **stub_settings(SmtpStub.closed_port)) do
        performs, recorded = count_attempts { perform_enqueued_jobs { queue_reset } }

        assert_equal MailDeliveryJob::ATTEMPTS, performs
        assert_equal 4, performs, "three retries"
        assert_equal [ 4 ], recorded, "recorded once, after the last attempt"
        assert_equal "connect", site.mail_failure["key"]
        assert_equal :failed, state
      end
    end
  end

  test "a refused login is recorded at once and not retried" do
    with_site_address(nil) do
      SmtpStub.start(:login_refused) do |port, stub|
        with_mail_state(:working, **stub_settings(port)) do
          performs, recorded = SmtpStub.trusted { count_attempts { perform_enqueued_jobs { queue_reset } } }

          assert_equal [ 1, [ 1 ] ], [ performs, recorded ]
          assert_equal({ "key" => "login", "line" => "535 5.7.8 Authentication failed for … (…)" }, site.mail_failure)
          assert_equal 1, stub.verbs.count("AUTH")
          assert_no_enqueued_jobs
        end
      end
    end
  end

  test "a refused sender is recorded at once and not retried" do
    with_site_address(nil) do
      SmtpStub.start(:sender_refused) do |port|
        with_mail_state(:working, **stub_settings(port)) do
          performs, recorded = SmtpStub.trusted { count_attempts { perform_enqueued_jobs { queue_reset } } }

          assert_equal [ 1, [ 1 ] ], [ performs, recorded ]
          assert_equal "sender", site.mail_failure["key"]
        end
      end
    end
  end

  test "a success through the stub records the send and verifies the settings it was queued under" do
    with_site_address(nil) do
      SmtpStub.start(:success) do |port, stub|
        with_mail_state(:untested, **stub_settings(port)) do
          SmtpStub.trusted { perform_enqueued_jobs { queue_reset } }

          assert_includes stub.messages.sole, "/cs-studio/password/edit#"
          assert_equal :working, state
        end
      end
    end
  end

  test "a success under an older fingerprint records the send and verifies nothing" do
    with_site_address(nil) do
      with_mail_state(:untested) do
        site.update_columns(mail_server: nil, mail_port: nil) # version: none (a test's setting)
        Current.site = nil
        queue_reset
        site.update_columns(mail_sender_address: "changed@example.test") # version: none (a test's setting)
        Current.site = nil

        assert_emails(1) { perform_enqueued_jobs }

        assert_not_nil site.mail_last_sent_at
        assert_nil site.mail_verified_at
        assert_equal :untested, state
      end
    end
  end

  test "a mail queued without a fingerprint is delivered and verifies nothing" do
    with_site_address(nil) do
      assert_emails(1) { perform_enqueued_jobs { PasswordsMailer.reset(@user, origin: "http://localhost:3000").deliver_later } }

      assert_not_nil site.mail_last_sent_at
      assert_nil site.mail_verified_at
    end
  end

  test "a mail the mailer decided not to build records nothing" do
    with_site_address(nil) do
      assert_no_emails { perform_enqueued_jobs { ApplicationMailer.queue(PasswordsMailer, :reset, @user) } }

      assert_nil site.mail_last_sent_at
      assert_nil site.mail_failed_at
    end
  end

  # Ruling T2b: a bug is no failed delivery. The job raises, so it fails as
  # Active Job's jobs do (in a worker: its backtrace, its log line and
  # Rails.error), and the dashboard is told nothing.
  test "a template that raises fails the job and records no mail failure" do
    with_mail_state(:working) do
      ApplicationMailer.queue(BrokenMailer, :broken, "bea@example.test")
      assert_raises(NoMethodError) { perform_enqueued_jobs }

      assert_nil site.mail_failed_at
      assert_equal :working, state
    end
  end

  test "a record deleted since the mail was queued fails the job and records no mail failure" do
    with_site_address(nil) do
      with_mail_state(:working) do
        queue_reset
        @user.sessions.delete_all
        @user.delete

        assert_raises(ActiveJob::DeserializationError) { perform_enqueued_jobs }

        assert_nil site.mail_failed_at
        assert_equal :working, state
      end
    end
  end

  test "the job's arguments hold no setting and no credential" do
    with_site_address(nil) do
      with_mail_state(:working, mail_server: "smtp.private-host.test", mail_port: 2525,
        mail_username: USERNAME, mail_password: PASSWORD, mail_sender_address: "sender@private-host.test") do
        queue_reset

        job = enqueued_jobs.sole
        serialized = job.inspect
        assert_equal "MailDeliveryJob", job["job_class"]
        [ USERNAME, PASSWORD, "private-host", "2525", "sender@" ].each { |secret| assert_not_includes serialized, secret }
        assert_equal MailSettings.current.fingerprint, job["arguments"].last.dig("params", "fingerprint")
        assert_includes serialized, @user.to_global_id.to_s, "a record goes as its id"
      end
    end
  end

  # Controller ruling T8a: an invite withdrawn before its mail went out is
  # an ordinary event. The job ends quietly, logs one info line with no
  # address, records nothing and raises nothing.
  test "an invite whose person was withdrawn before the mail went out is discarded quietly" do
    with_site_address("https://cms.example.test") do
      with_mail_state(:working) do
        invited = invited_user("withdrawn-early@example.com")
        ApplicationMailer.queue(InvitesMailer, :invite, invited, inviter: users(:two))
        invited.destroy!

        log = capture_log do
          assert_no_emails { perform_enqueued_jobs }
        end

        assert_includes log, "An invitation mail was not sent: the invite was withdrawn before it went out."
        assert_not_includes log, "withdrawn-early"
        assert_nil site.mail_failed_at
        assert_equal :working, state
      end
    end
  end

  test "an invite whose inviter is gone still fails as a deleted record does" do
    with_site_address("https://cms.example.test") do
      with_mail_state(:working) do
        inviter = User.create!(email_address: "inviter@example.com", password: "a-long-password-1")
        ApplicationMailer.queue(InvitesMailer, :invite, invited_user("kept@example.com"), inviter: inviter)
        inviter.destroy!

        assert_raises(ActiveJob::DeserializationError) { perform_enqueued_jobs }
        assert_nil site.mail_failed_at
      end
    end
  end
end
