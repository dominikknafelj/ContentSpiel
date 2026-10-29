require "test_helper"

# Delivery with the site's settings (spec, decisions 4 and 5, "A failure's
# sentence", "Development and test"), against the local SMTP stub
# (test/support/smtp_stub.rb): 127.0.0.1 and an ephemeral port, never the
# network. `deliver_now_and_record` is the test mail's path; the job's own
# tests are test/jobs/mail_delivery_job_test.rb.
class ApplicationMailerTest < ActionMailer::TestCase
  include LogCapture

  USERNAME = "ana-login@example.test".freeze
  PASSWORD = "pw-Secr3t-9".freeze

  class ProbeMailer < ApplicationMailer
    def probe(to)
      mail(to: to, subject: "Probe") { |format| format.text { render plain: "Hello from the probe." } }
    end

    # A mailer whose template raises: a bug, never a failed delivery.
    def broken(to)
      mail(to: to, subject: "Broken") { |format| format.text { raise NoMethodError, "undefined method 'title' for nil" } }
    end
  end

  def stub_settings(port, security: "starttls", login: true, **columns)
    columns = { mail_server: SmtpStub::HOST, mail_port: port, mail_security: security,
                mail_sender_name: "Test Site", mail_sender_address: "no-reply@example.test" }.merge(columns)
    columns.merge!(mail_username: USERNAME, mail_password: PASSWORD) if login
    columns
  end

  def send_probe = ApplicationMailer.deliver_now_and_record(ProbeMailer.probe("bea@example.test"))

  def site = SiteSetting.instance.reload

  test "a mail sent through the stub reaches it with the effective sender, over the login, and records a success" do
    SmtpStub.start(:success) do |port, stub|
      with_mail_state(:untested, **stub_settings(port)) do
        SmtpStub.trusted { assert_nil send_probe }

        assert_equal %w[EHLO STARTTLS EHLO AUTH MAIL RCPT DATA QUIT], stub.verbs
        assert_includes stub.commands, "MAIL FROM:<no-reply@example.test>"
        assert_includes stub.commands, "AUTH PLAIN #{Base64.strict_encode64("\0#{USERNAME}\0#{PASSWORD}")}", "the login, after STARTTLS"
        assert_match(/^From: Test Site <no-reply@example\.test>\r?$/, stub.messages.sole)
        assert_includes stub.messages.sole, "Hello from the probe."

        assert_equal :working, MailSettings.current.state
        assert_not_nil site.mail_last_sent_at
        assert_empty ActionMailer::Base.deliveries, "the stand-in delivered nothing: the server is set"
      end
    end
  end

  # Ruling T2a: `none` is plain SMTP. The stub offers STARTTLS, and the client
  # does not take it up, so a host's relay is spoken to as it asked.
  test "none is plain SMTP: no STARTTLS is sent although the server offers it" do
    SmtpStub.start(:success) do |port, stub|
      with_mail_env("MAIL_SMTP_SECURITY" => "none") do
        with_mail_state(:untested, **stub_settings(port, login: false)) do
          assert_nil send_probe

          assert_equal %w[EHLO MAIL RCPT DATA QUIT], stub.verbs
          assert_equal :working, MailSettings.current.state
        end
      end
    end
  end

  # STARTTLS is REQUIRED, never "if offered": a server that refuses it, and
  # one that does not offer it (or someone on the way who struck it from the
  # answer), get no login and no mail.
  test "starttls sends STARTTLS and fails as security when the server refuses it or does not offer it, before any login" do
    SmtpStub.start(:starttls_refused) do |port, stub|
      with_mail_state(:untested, **stub_settings(port)) do
        failure = send_probe

        assert_equal [ "security", "454 4.7.0 TLS not available" ], [ failure.key, failure.line ]
        assert_equal %w[EHLO STARTTLS], stub.verbs
      end
    end

    SmtpStub.start(:no_starttls) do |port, stub|
      with_mail_state(:untested, **stub_settings(port)) do
        assert_equal "security", send_probe.key
        assert_equal %w[EHLO], stub.verbs, "no STARTTLS asked of a server that offers none, and nothing after it"
      end
    end
  end

  test "each failing script records its key and line and hides nothing: ready? stays true for a verified site" do
    expected = {
      login_refused: [ "login", "535 5.7.8 Authentication failed for … (…)" ],
      sender_refused: [ "sender", "550 5.7.1 Sender address rejected" ],
      starttls_refused: [ "security", "454 4.7.0 TLS not available" ]
    }
    expected.each do |script, (key, line)|
      SmtpStub.start(script) do |port|
        with_mail_state(:working, **stub_settings(port)) do
          failure = SmtpStub.trusted { send_probe }

          assert_equal [ key, line ], [ failure.key, failure.line ], script
          assert_equal({ "key" => key, "line" => line }, site.mail_failure, script)
          assert_not_nil site.mail_failed_at
          assert_equal :failed, MailSettings.current.state, script
          assert MailSettings.current.ready?, "#{script}: a failure hides nothing"
        end
      end
    end

    with_mail_state(:working, **stub_settings(SmtpStub.closed_port)) do
      failure = send_probe

      assert_equal "connect", failure.key
      assert_match(/\AConnection refused/, failure.line)
      assert_equal "Could not reach 127.0.0.1 on port #{site.mail_port}. Check server and port.",
        failure.sentence(server: SmtpStub::HOST, port: site.mail_port)
      assert MailSettings.current.ready?
    end
  end

  # Ruling T2b: what the exchange raises is a failed delivery, whatever it
  # is; a server that hangs up answers no SMTP reply at all.
  test "an unexpected error inside the SMTP exchange is recorded as other" do
    SmtpStub.start(:hang_up) do |port, stub|
      with_mail_state(:working, **stub_settings(port)) do
        failure = SmtpStub.trusted { send_probe }

        assert_equal "other", failure.key
        assert_includes stub.verbs, "MAIL"
        assert_equal "other", site.mail_failure["key"]
        assert_equal :failed, MailSettings.current.state
      end
    end
  end

  # Ruling T2b: an error raised before the delivery is a bug. It is raised
  # on, and the site's mail is not called failed for it.
  test "a mailer or template that raises is raised on and recorded as no mail failure" do
    SmtpStub.start(:success) do |port, stub|
      with_mail_state(:working, **stub_settings(port)) do
        assert_raises(NoMethodError) do
          SmtpStub.trusted { ApplicationMailer.deliver_now_and_record(ProbeMailer.broken("bea@example.test")) }
        end

        assert_empty stub.commands, "nothing was sent"
        assert_nil site.mail_failed_at
        assert_equal :working, MailSettings.current.state
      end
    end
  end

  # Review Focus 3: the test mail is sent in the request, so a server that
  # takes the connection and never answers must not hang the Settings page.
  test "a server that never answers fails as connect within the timeouts" do
    stub_const(MailSettings, :READ_TIMEOUT, 1) do
      SmtpStub.start(:silent) do |port|
        with_mail_state(:untested, **stub_settings(port)) do
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          failure = send_probe
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

          assert_equal "connect", failure.key
          assert_operator elapsed, :<, 20
          assert_operator elapsed, :<, 5, "the lowered read timeout is the one in force"
        end
      end
    end
  end

  test "no log line of a send holds the password or the username" do
    secrets = [ USERNAME, PASSWORD, Base64.strict_encode64("\0#{USERNAME}\0#{PASSWORD}"),
                Base64.strict_encode64(USERNAME), Base64.strict_encode64(PASSWORD) ]
    %i[success login_refused].each do |script|
      SmtpStub.start(script) do |port|
        with_mail_state(:working, **stub_settings(port)) do
          log = capture_log do
            SmtpStub.trusted do
              send_probe
              perform_enqueued_jobs { ApplicationMailer.queue(ProbeMailer, :probe, "bea@example.test") }
            end
          end

          assert_includes log, "MailDeliveryJob", "the capture holds the job's lines"
          assert_includes log, "ProbeMailer", "and the mailer's"
          secrets.each { |secret| assert_not_includes log.downcase, secret.downcase, "#{script}: #{secret}" }
        end
      end
    end
  end

  # Plan Ruling 1: with no server set the test environment's own method
  # stands in for SMTP, and a send through it is a send that succeeded.
  test "with no server set the stand-in delivers and the send counts as a success" do
    with_mail_state(:untested, mail_server: nil, mail_port: nil, mail_sender_address: "no-reply@example.test") do
      assert MailSettings.current.stand_in?

      assert_emails(1) { assert_nil send_probe }
      assert_equal [ "no-reply@example.test" ], ActionMailer::Base.deliveries.sole.from
      assert_equal :working, MailSettings.current.state
    end
  end

  # No network in tests: a server that is not this machine is never dialled
  # from the test environment; the stand-in takes the mail, so a test of a
  # screen can put the site in :working with smtp.example.test and still
  # read the mail it sent.
  test "in the test environment a server that is not this machine is never dialled: the stand-in takes the mail" do
    with_mail_state(:working) do
      assert_emails(1) { assert_nil send_probe }
      assert_equal :working, MailSettings.current.state
    end
  end

  test "settings that are not complete send nothing, say so once, and record nothing" do
    with_mail_state(:not_set_up) do
      log = capture_log do
        assert_no_emails { assert_nil send_probe }
      end

      assert_equal [ "[ContentSpiel] A mail was not sent: outgoing mail is not set up." ], log.lines.map(&:strip).grep(/ContentSpiel/)
      assert_nil site.mail_last_sent_at
      assert_nil site.mail_failed_at
    end
  end

  test "queue hands the job the fingerprint of the settings it was queued under, and no setting" do
    with_mail_state(:working) do
      ApplicationMailer.queue(ProbeMailer, :probe, "bea@example.test")

      job = enqueued_jobs.sole
      assert_equal "MailDeliveryJob", job["job_class"]
      assert_equal [ "ApplicationMailerTest::ProbeMailer", "probe", "deliver_now" ], job["arguments"].first(3)
      assert_equal MailSettings.current.fingerprint, job["arguments"].last.dig("params", "fingerprint")
    end
  end

  test "the sender is the effective one, with its name" do
    with_mail_state(:working, mail_sender_name: "Ana's \"Site\"", mail_sender_address: "hello@example.test") do
      assert_equal "\"Ana's \\\"Site\\\"\" <hello@example.test>", ProbeMailer.probe("bea@example.test").header[:from].value
    end
  end
end
