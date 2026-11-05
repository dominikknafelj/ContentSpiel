require "test_helper"

# A form's mail that failed because mail
# was not set up (`not_ready`) is sent again by itself once mail is set up,
# through Send again's own path (`Forms::Resend`, then `Forms::DeliveryJob`),
# as the trusted nil actor on :system, so each one is a `form_submission
# .resent` event that reads "System". Mail can be set up by host variables
# alone, which is why a recurring job asks rather than a save hooking it.
class Forms::ResendNotReadyJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper
  include EncryptionKeys

  def failed(key: Forms::Destinations::Mail::NOT_READY, form: forms(:contact), destination: form_destinations(:contact_mail))
    submission = Forms::Submission.create!(form: form, locale: "en",
      answers: [ { "key" => "f_name0001", "type" => "short_text", "label" => "Your name", "value" => "Ada", "display" => "Ada" } ])
    delivery = submission.deliveries.create!(kind: "mail", destination: destination)
    delivery.record_failed!(key: key, line: nil, at: 1.hour.ago)
    delivery
  end

  def resent_events = Audit::Event.where(action: "form_submission.resent").order(:id)

  test "while mail is not set up nothing is sent again" do
    delivery = failed

    with_mail_state(:not_set_up) { Forms::ResendNotReadyJob.perform_now }

    assert delivery.reload.failed?
    assert_no_enqueued_jobs(only: Forms::DeliveryJob)
    assert_empty resent_events
  end

  test "once mail is set up the mails that waited for it are sent, recorded as System's Send again" do
    delivery = failed
    with_mail_state(:untested) do
      assert_emails(1) do
        perform_enqueued_jobs(only: Forms::DeliveryJob) { Forms::ResendNotReadyJob.perform_now }
      end
    end

    # Sent, and the form keeps nothing, so the submission went with it.
    assert_not Forms::Submission.exists?(delivery.submission_id)
    event = resent_events.sole
    assert_equal [ forms(:contact), nil, "system" ], [ event.subject, event.user_id, event.channel ]
    assert_equal({ "submission_id" => delivery.submission_id, "destination" => "mail" }, event.metadata)
  end

  # Mail set up by the host's variables alone: no save, the same answer.
  test "mail set up by host variables alone is enough" do
    delivery = failed
    with_mail_state(:not_set_up) do
      with_mail_env("MAIL_SMTP_SERVER" => "smtp.env.test", "MAIL_SMTP_PORT" => "587", "MAIL_SMTP_SECURITY" => "starttls",
        "MAIL_SENDER_ADDRESS" => "forms@env.test") do
        assert MailSettings.current.complete?
        Forms::ResendNotReadyJob.perform_now
      end
    end

    assert delivery.reload.waiting?
    assert_enqueued_with(job: Forms::DeliveryJob, args: [ delivery ])
  end

  test "only failed not_ready mails of kept forms whose destination is still there are sent again" do
    other_key = failed(key: "login")
    removed = failed(destination: nil)
    trashed = failed.tap { |delivery| delivery.submission.update_columns(form_id: forms(:newsletter).id) } # version: none (a test's row)
    sent = failed.tap { |delivery| delivery.record_sent!(at: Time.current) }
    Current.set(actor: users(:one)) { assert Trash::Move.call(forms(:newsletter)).ok? }
    due = failed

    with_mail_state(:untested) { Forms::ResendNotReadyJob.perform_now }

    assert due.reload.waiting?
    [ other_key, removed, trashed ].each { |delivery| assert delivery.reload.failed?, delivery.inspect }
    assert sent.reload.sent?
    assert_equal [ due.submission_id ], resent_events.map { |event| event.metadata["submission_id"] }
  end

  test "without encryption keys nothing is sent again: the answers could not be read" do
    delivery = failed
    with_mail_state(:untested) { without_encryption_keys { Forms::ResendNotReadyJob.perform_now } }

    assert delivery.reload.failed?
    assert_empty resent_events
  end
end
