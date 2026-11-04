require "test_helper"

# A visitor's send as it is stored (forms plan, Task 3): the answers
# encrypted, readable only with the keys they were written with, and a
# submission's deliveries saying whether it has gone everywhere.
class Forms::SubmissionTest < ActiveSupport::TestCase
  ANSWERS = [ { "key" => "f_mail0002", "type" => "email", "label" => "Email address", "value" => "bea@example.com", "display" => "bea@example.com" } ].freeze

  def submission = Forms::Submission.create!(form: forms(:newsletter), locale: "en", answers: ANSWERS)

  test "the answers are stored encrypted and read back as they were written" do
    record = submission
    raw = Forms::Submission.connection.select_value(Forms::Submission.where(id: record.id).select(:answers).to_sql)
    assert_not_includes raw, "bea@example.com"
    assert_equal ANSWERS, Forms::Submission.find(record.id).answers
    assert_predicate record, :readable?
  end

  test "a submission written under other keys is not readable, and says so without raising" do
    record = submission
    other = ActiveRecord::Encryption::DerivedSecretKeyProvider.new("keys that are not the site's")
    ActiveRecord::Encryption.with_encryption_context(key_provider: other) do
      reloaded = Forms::Submission.find(record.id)
      assert_not reloaded.readable?
    end
  end

  test "delivered when every delivery is sent, undelivered when one failed" do
    record = submission
    assert_predicate record, :delivered?, "nothing to deliver is delivered"

    first = record.deliveries.create!(kind: "mail")
    second = record.deliveries.create!(kind: "mail")
    assert_equal %w[waiting waiting], record.deliveries.reload.map(&:state)
    assert_not record.delivered?

    first.record_sent!(at: Time.current)
    second.record_failed!(key: "login", line: "535", at: Time.current)
    record.deliveries.reload
    assert_not record.delivered?
    assert_predicate record, :undelivered?
    assert_equal({ "key" => "login", "line" => "535" }, second.reload.failure)

    second.resend!
    assert_equal [ "waiting", nil, nil, 0 ], [ second.reload.state, second.failure, second.failed_at, second.attempts ]
    second.record_attempt!
    second.record_sent!(at: Time.current)
    assert_equal 1, second.reload.attempts
    assert_predicate record.deliveries.reload.then { record }, :delivered?
  end

  test "a delivery's state is one of three" do
    assert_raises(ActiveRecord::RecordInvalid) { submission.deliveries.create!(kind: "mail", state: "lost") }
  end

  test "the answers are filtered from a request's logged parameters to the forms endpoint, and nowhere else" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    sent = { "controller" => "form_sends", "action" => "create", "form_id" => "4", "website" => "",
             "answers" => { "f_name0001" => "Ada Lovelace", "f_mail0001" => "ada@example.com" } }
    filtered = filter.filter(sent)
    assert_equal({ "f_name0001" => "[FILTERED]", "f_mail0001" => "[FILTERED]" }, filtered["answers"])
    assert_equal [ "4", "" ], filtered.values_at("form_id", "website")
    assert_equal "Ada Lovelace", sent.dig("answers", "f_name0001"), "the request's own parameters keep the answers"
    assert_equal "[FILTERED]", filter.filter("controller" => "form_sends", "answers" => "Ada")["answers"]

    snapshot = { "faq_answers" => "Yes, we ship", "answers" => "plain" }
    assert_equal snapshot, Audit::Snapshot.scrub(snapshot), "an audit snapshot keeps a key called answers, or containing it"
    assert_equal({ "controller" => "admin/forms", "answers" => { "f_name0001" => "Kept" } },
      filter.filter("controller" => "admin/forms", "answers" => { "f_name0001" => "Kept" }), "another controller's answers are its own business")
  end
end
