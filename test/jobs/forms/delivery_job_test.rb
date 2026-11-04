require "test_helper"

# One delivery of one submission to one destination (forms plan, Task 3,
# decisions 6 and 11): the job asks the destination's deliverer, records the
# delivery sent or failed, and retries what is worth retrying. The mail
# destination delivers through `ApplicationMailer.deliver_in_job`, which keeps
# mail's rules: the site's mail state records the send (verifying the
# settings only under the fingerprint the delivery was queued under), a
# connection failure is retried three times and recorded once, after the
# last, anything else of the exchange at once, and the line is scrubbed.
class Forms::DeliveryJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper
  include LogCapture

  USERNAME = "forms-login@example.test".freeze
  PASSWORD = "forms-Pa55-w0rd".freeze
  ANSWERS = { "f_name0001" => "Ada Lovelace", "f_mail0001" => "ada@example.com", "f_text0001" => "Hello there" }.freeze

  # A destination type a gem could register, with a secret.
  module Hook
    class << self
      attr_accessor :answer

      def deliver(delivery, final_attempt:)
        answer.call(delivery, final_attempt)
      end
    end
  end

  teardown { Rails.application.reloader.prepare! if @registered }

  def register_hook(&answer)
    @registered = true
    Hook.answer = answer
    Forms::DestinationTypes.register("acme/hook", label: "Hook", deliverer: Hook) do |d|
      d.field :list, :string, required: true
      d.secret :api_key
    end
  end

  # A send as the trusted actor: who sends is Forms::Submit's test's
  # business, and only the tests about the visitor act as it.
  def send_form(form = forms(:contact), answers = ANSWERS)
    result = Forms::Submit.call(form, answers: answers, locale: "en")
    assert result.ok?, result.errors.inspect
    result.record
  end

  def stub_settings(port)
    { mail_server: SmtpStub::HOST, mail_port: port, mail_security: "starttls",
      mail_username: USERNAME, mail_password: PASSWORD, mail_sender_address: "no-reply@example.test" }
  end

  def site = SiteSetting.instance.reload

  def performs_of
    performs = 0
    counting = ->(event) { performs += 1 if event.payload[:job].is_a?(Forms::DeliveryJob) }
    ActiveSupport::Notifications.subscribed(counting, "perform_start.active_job") { yield }
    performs
  end

  test "a mail delivery is sent, recorded sent, and the site's mail state records the send" do
    with_mail_state(:failed) do
      submission = nil
      assert_emails(1) { perform_enqueued_jobs(only: Forms::DeliveryJob) { submission = send_form } }
      delivery = submission.deliveries.first

      mail = ActionMailer::Base.deliveries.last
      assert_equal [ "office@example.com" ], mail.to
      assert_equal [ "ada@example.com" ], mail.reply_to
      assert_not_nil site.mail_last_sent_at
      assert_equal :working, MailSettings.current(site).state, "a send under the fingerprint it was queued with verifies the settings"
      assert_not Forms::Delivery.exists?(delivery.id), "Contact keeps nothing: the delivered submission goes, its delivery with it"
    end
  end

  test "a mail queued under older settings is sent and verifies nothing" do
    with_mail_state(:failed) do
      send_form
      # The settings changed since, and were tested and failed since: ready,
      # and not verified under the fingerprint the delivery was queued with.
      site.update_columns(mail_sender_address: "changed@example.test") # version: none (a test's setting)
      site.update_columns(mail_verified_fingerprint: MailSettings.current(site).fingerprint) # version: none (a test's setting)
      Current.site = nil
      assert_equal :failed, MailSettings.current(site).state
      last_sent = site.mail_last_sent_at

      assert_emails(1) { perform_enqueued_jobs(only: Forms::DeliveryJob) }
      assert_operator site.mail_last_sent_at, :>, last_sent, "the send is recorded"
      assert_equal :failed, MailSettings.current(site).state, "and verifies nothing: it was queued under other settings"
    end
  end

  test "a form that does not keep deletes the submission once every delivery is sent, recorded as delivered" do
    form = forms(:contact)
    form.destinations.create!(kind: "mail", position: 1, settings: { "recipients" => "sales@example.com" })
    with_mail_state(:working) do
      submission = send_form(form)
      first, second = submission.deliveries.order(:id)

      perform_enqueued_jobs(only: Forms::DeliveryJob) do
        Forms::DeliveryJob.perform_now(first)
        assert Forms::Submission.exists?(submission.id), "one of two sent: still waiting for the other"
        assert_equal "sent", first.reload.state
        Forms::DeliveryJob.perform_now(second)
      end

      assert_not Forms::Submission.exists?(submission.id)
      event = Audit::Event.where(action: "form_submissions.deleted").sole
      assert_equal({ "count" => 1, "reason" => "delivered", "submission_ids" => [ submission.id ] }, event.metadata)
      assert_equal [ nil, "system" ], [ event.user_id, event.channel ]
    end
  end

  test "a form that keeps keeps the submission once it is delivered" do
    form = forms(:newsletter)
    form.destinations.create!(kind: "mail", position: 0, settings: { "recipients" => "office@example.com" })
    with_mail_state(:working) do
      submission = nil
      perform_enqueued_jobs(only: Forms::DeliveryJob) { submission = send_form(form, { "f_mail0002" => "bea@example.com", "f_okay0002" => "1" }) }

      assert_equal "sent", submission.deliveries.reload.sole.state
      assert Forms::Submission.exists?(submission.id)
    end
  end

  test "a connection failure is retried three times and recorded once, failed with the connect key, after the last" do
    with_site_address(nil) do
      with_mail_state(:working, **stub_settings(SmtpStub.closed_port)) do
        submission = nil
        recorded = []
        record = MailSettings.method(:record_failure!)
        performs = with_singleton_override(MailSettings, :record_failure!, ->(**args) { recorded << args[:key]; record.call(**args) }) do
          performs_of { perform_enqueued_jobs(only: Forms::DeliveryJob) { submission = send_form } }
        end

        delivery = submission.deliveries.sole.reload
        assert_equal 4, Forms::DeliveryJob::ATTEMPTS, "three retries"
        assert_equal Forms::DeliveryJob::ATTEMPTS, performs
        assert_equal [ "connect" ], recorded, "the site's mail state is told once, after the last attempt"
        assert_equal [ "failed", "connect", 4 ], [ delivery.state, delivery.failure["key"], delivery.attempts ]
        assert_not_nil delivery.failed_at
        assert Forms::Submission.exists?(submission.id), "it keeps the submission while a delivery has failed"
        assert_predicate submission.reload, :undelivered?
      end
    end
  end

  test "a refused login is recorded at once and not retried" do
    with_site_address(nil) do
      SmtpStub.start(:login_refused) do |port|
        with_mail_state(:working, **stub_settings(port)) do
          submission = nil
          performs = SmtpStub.trusted { performs_of { perform_enqueued_jobs(only: Forms::DeliveryJob) { submission = send_form } } }

          delivery = submission.deliveries.sole.reload
          assert_equal 1, performs
          assert_equal [ "failed", "login" ], [ delivery.state, delivery.failure["key"] ]
          assert_equal "535 5.7.8 Authentication failed for … (…)", delivery.failure["line"]
          assert_equal "login", site.mail_failure["key"]
          assert_no_enqueued_jobs(only: Forms::DeliveryJob)
        end
      end
    end
  end

  test "while mail is not set up the delivery fails with not_ready and is not retried" do
    with_mail_state(:not_set_up) do
      submission = nil
      performs = nil
      assert_no_emails { performs = performs_of { perform_enqueued_jobs(only: Forms::DeliveryJob) { submission = send_form } } }

      delivery = submission.deliveries.sole.reload
      assert_equal [ 1, "failed", "not_ready", nil ], [ performs, delivery.state, delivery.failure["key"], delivery.failure["line"] ]
      assert_nil site.mail_failed_at, "a mail not set up is no failed send"
      assert Forms::Submission.exists?(submission.id)
    end
  end

  test "with mail saved and never tested a form mail is sent, and verifies the settings it was queued under" do
    with_mail_state(:untested) do
      submission = nil
      assert_emails(1) { perform_enqueued_jobs(only: Forms::DeliveryJob) { submission = send_form(forms(:newsletter).tap { |form| form.destinations.create!(kind: "mail", settings: { "recipients" => "office@example.com" }) }, { "f_mail0002" => "bea@example.com", "f_okay0002" => "1" }) } }

      assert_equal "sent", submission.deliveries.reload.sole.state
      assert_equal :working, MailSettings.current(site).state
    end
  end

  test "a failure's line holds no answer of the submission" do
    register_hook { |_delivery, _final| raise Forms::DestinationTypes::Failed.new(key: "refused", line: "409 contact ADA@example.com (Ada Lovelace, Ada) already exists") }
    form = forms(:contact)
    form.destinations.destroy_all
    form.destinations.create!(kind: "acme/hook", position: 0, settings: { "list" => "news" })

    submission = nil
    perform_enqueued_jobs(only: Forms::DeliveryJob) { submission = send_form(form, ANSWERS.merge("f_name0001" => "Ada Lovelace")) }

    line = submission.deliveries.reload.sole.failure["line"]
    assert_equal "409 contact … (…, Ada) already exists", line, "every answer, the longest first, in any case; a part of one is not an answer"
  end

  test "an error that is no failed delivery fails the delivery with the key error and the job, and blames no setting" do
    register_hook { |_delivery, _final| raise NoMethodError, "undefined method 'name' for nil" }
    form = forms(:contact)
    form.destinations.destroy_all
    form.destinations.create!(kind: "acme/hook", position: 0, settings: { "list" => "news" })

    with_mail_state(:working) do
      submission = send_form(form)
      assert_raises(NoMethodError) { perform_enqueued_jobs(only: Forms::DeliveryJob) }

      delivery = submission.deliveries.reload.sole
      assert_equal [ "failed", "error", nil ], [ delivery.state, delivery.failure["key"], delivery.failure["line"] ]
      assert_predicate submission.reload, :undelivered?
      assert_nil site.mail_failed_at
      assert_equal :working, MailSettings.current(site).state
    end
  end

  test "a mail whose answers the keys can no longer read fails with the key error, and blames no setting" do
    with_mail_state(:working) do
      submission = send_form
      other = ActiveRecord::Encryption::DerivedSecretKeyProvider.new("keys that are not the site's")
      ActiveRecord::Encryption.with_encryption_context(key_provider: other) do
        assert_raises(ActiveRecord::Encryption::Errors::Decryption) { perform_enqueued_jobs(only: Forms::DeliveryJob) }
      end

      delivery = submission.deliveries.reload.sole
      assert_equal [ "failed", "error" ], [ delivery.state, delivery.failure["key"] ]
      assert_nil site.mail_failed_at
    end
  end

  test "only a failed delivery is sent again: a sent or waiting one is left as it is" do
    delivery = send_form.deliveries.sole
    assert_not delivery.resend!, "a waiting one"
    delivery.record_sent!(at: Time.current)
    assert_not delivery.resend!, "a sent one"
    assert_equal "sent", delivery.reload.state

    delivery.record_failed!(key: "login", line: "535", at: Time.current)
    assert delivery.resend!
    assert_equal [ "waiting", nil, 0 ], [ delivery.state, delivery.failure, delivery.attempts ]
  end

  test "a failure's line holds no secret value of the destination" do
    secret = "sk-live-Secr3t-value"
    register_hook { |_delivery, _final| raise Forms::DestinationTypes::Failed.new(key: "refused", line: "401 the key #{secret} (#{secret.upcase}) is no good") }
    form = forms(:contact)
    hook = form.destinations.create!(kind: "acme/hook", position: 1, settings: { "list" => "news" })
    hook.write_secrets!("api_key" => secret)

    submission = nil
    with_mail_state(:working) { perform_enqueued_jobs(only: Forms::DeliveryJob) { submission = send_form(form) } }

    failed = submission.deliveries.find_by!(destination: hook)
    assert_equal [ "failed", "refused" ], [ failed.state, failed.failure["key"] ]
    assert_equal "401 the key … (…) is no good", failed.failure["line"]
  end

  test "a destination's deliverer that asks for a retry is retried, told which attempt is the last, and given up on after it" do
    finals = []
    register_hook { |_delivery, final| finals << final; raise Forms::DestinationTypes::Retry }
    form = forms(:contact)
    form.destinations.destroy_all
    form.destinations.create!(kind: "acme/hook", position: 0, settings: { "list" => "news" })

    submission = nil
    perform_enqueued_jobs(only: Forms::DeliveryJob) { submission = send_form(form) }

    assert_equal [ false, false, false, true ], finals
    delivery = submission.deliveries.sole.reload
    assert_equal [ "failed", "gave_up", 4 ], [ delivery.state, delivery.failure["key"], delivery.attempts ]
  end

  test "a delivery whose destination was removed, or whose type is not registered, fails and says why" do
    form = forms(:contact)
    submission = send_form(form)
    delivery = submission.deliveries.sole
    form_destinations(:contact_mail).destroy!

    with_mail_state(:working) { perform_enqueued_jobs(only: Forms::DeliveryJob) }
    assert_equal [ "failed", "no_destination" ], [ delivery.reload.state, delivery.failure["key"] ]

    dormant = form.destinations.create!(kind: "mail", position: 0, settings: { "recipients" => "office@example.com" })
    dormant.update_columns(kind: "gone/crm") # version: none (a gem's destination that is no longer installed)
    other = send_form(form).deliveries.sole
    perform_enqueued_jobs(only: Forms::DeliveryJob)
    assert_equal [ "failed", "unknown_destination" ], [ other.reload.state, other.failure["key"] ]
  end

  test "a delivery that is no longer waiting is not delivered again" do
    with_mail_state(:working) do
      delivery = send_form.deliveries.sole
      delivery.record_sent!(at: Time.current)
      assert_no_emails { perform_enqueued_jobs(only: Forms::DeliveryJob) }
    end
  end

  test "the job's arguments are a delivery's Global ID and no answer" do
    delivery = send_form.deliveries.sole
    job = enqueued_jobs.find { |queued| queued["job_class"] == "Forms::DeliveryJob" }

    assert_equal [ { "_aj_globalid" => delivery.to_global_id.to_s } ], job["arguments"]
    assert_equal "default", job["queue_name"]
    ANSWERS.each_value { |typed| assert_not_includes job.inspect, typed }
  end

  test "a delivery deleted before its job ran is discarded with one line that names no address" do
    with_mail_state(:working) do
      submission = send_form
      assert Forms::DeleteSubmissions.call(forms(:contact), ids: [ submission.id ]).ok?

      log = capture_log { assert_no_emails { perform_enqueued_jobs(only: Forms::DeliveryJob) } }

      assert_includes log, "[ContentSpiel] A form's delivery was not sent: its submission was deleted before it went out."
      assert_not_includes log, "@example.com"
      assert_nil site.mail_failed_at
    end
  end

  # Personal data reaches no log line and no span (forms plan, Global
  # Constraints): not the answers, not the visitor's address, not the
  # recipients'. The send is traced (the job's consumer root and Action
  # Mailer's delivery), and everything the job and the mailer log at info
  # and above is read: at debug Action Mailer logs every mail it delivers in
  # full, which is why production's level stays at info (docs/reference/
  # mail.md, and the boot's warning, `HostSettings.log_level_warning`).
  test "a delivery's spans and log lines hold no answer and no address" do
    exporter = Rails.application.config.x.otel_test_exporter
    exporter.reset
    log = nil
    with_mail_state(:working) do
      log = capture_log do
        Rails.logger.level = Logger::INFO # the capture's own logger, put back with it
        assert_emails(1) { perform_enqueued_jobs(only: Forms::DeliveryJob) { send_form } }
      end
    end

    spans = exporter.finished_spans
    assert spans.any? { |span| span.kind == :consumer }, "the job's span is recorded: #{spans.map(&:name)}"
    text = spans.map { |span| [ span.name, span.attributes.to_a, Array(span.events).map { |event| [ event.name, event.attributes.to_a ] } ].flatten.compact.join(" ") }.join("\n")
    assert_includes log, "Forms::DeliveryJob", "the job's lines were captured, so the check below can fail"
    [ *ANSWERS.values, "office@example.com" ].each do |personal|
      assert_not_includes text, personal, "a span"
      assert_not_includes log, personal, "a log line"
    end
  end
end
