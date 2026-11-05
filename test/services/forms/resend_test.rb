require "test_helper"

# Send again: a FAILED delivery goes back
# to waiting under the mail settings as they are now and is queued again
# after the commit, recorded as `form_submission.resent` on the form by ids
# only. A delivery that is sent or still waiting is refused, and nothing is
# written or queued.
class Forms::ResendTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { Current.actor = users(:one) }

  def delivery(state = :failed)
    submission = Forms::Submission.create!(form: forms(:contact), locale: "en",
      answers: [ { "key" => "f_mail0001", "type" => "email", "label" => "Email address", "value" => "ada@example.com", "display" => "ada@example.com" } ])
    record = submission.deliveries.create!(kind: "mail", destination: form_destinations(:contact_mail))
    case state
    when :failed then record.record_failed!(key: "login", line: "535 refused", at: 1.hour.ago)
    when :sent then record.record_sent!(at: 1.hour.ago)
    end
    record
  end

  def event = Audit::Event.where(action: "form_submission.resent").order(:id).last

  test "a failed delivery is sent again, recorded, and queued after commit" do
    failed = delivery
    failed.update_columns(attempts: 4)

    result = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      result = Forms::Resend.call(failed)
      assert_no_enqueued_jobs(only: Forms::DeliveryJob)
    end

    assert result.ok?, result.errors.to_sentence
    failed.reload
    assert_equal [ "waiting", nil, nil, 0 ], [ failed.state, failed.failure, failed.failed_at, failed.attempts ]
    assert_enqueued_with(job: Forms::DeliveryJob, args: [ failed ])

    assert_equal [ forms(:contact), users(:one).id, "Contact" ], [ event.subject, event.user_id, event.subject_label ]
    assert_equal({ "submission_id" => failed.submission_id, "destination" => "mail" }, event.metadata)
    assert_nil event.snapshot
    assert_not_includes event.attributes.to_json, "ada@example.com", "no answer is in the event"
  end

  test "a delivery of a trashed form is refused, and nothing is written or queued" do
    failed = delivery
    assert Trash::Move.call(forms(:contact)).ok?

    assert_no_difference -> { Audit::Event.where(action: "form_submission.resent").count } do
      result = Forms::Resend.call(failed)
      assert_not result.ok?
      assert_not result.denied?
      assert_equal [ Forms::Resend.sentence(:trashed) ], result.errors
    end
    assert failed.reload.failed?
    assert_no_enqueued_jobs(only: Forms::DeliveryJob)
  end

  test "a sent or waiting delivery is refused" do
    [ delivery(:sent), delivery(:waiting) ].each do |record|
      state = record.state
      assert_no_difference -> { Audit::Event.count } do
        result = Forms::Resend.call(record)
        assert_not result.ok?
        assert_not result.denied?
        assert_equal [ Forms::Resend.sentence(:not_failed) ], result.errors
      end
      assert_equal state, record.reload.state
    end
    assert_no_enqueued_jobs(only: Forms::DeliveryJob)
  end
end
