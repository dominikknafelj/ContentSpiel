require "test_helper"

# A visitor's send (forms plan, Task 3; owner's ruling 2): the answers are
# cleaned against the form's fields and written as ONE encrypted submission
# with a waiting delivery per destination, each delivered by a job queued
# after the commit. The visitor (`AccessControl::VISITOR`) is allowed exactly
# this, on :public; the audit event names the submission by id and nothing
# of what was typed. Without encryption keys a form takes no answers at all.
class Forms::SubmitTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include EncryptionKeys

  ANSWERS = { "f_name0001" => "Ada Lovelace", "f_mail0001" => "ada@example.com", "f_text0001" => "Hello <b>there</b>" }.freeze
  TYPED = [ "Ada Lovelace", "ada@example.com", "Hello" ].freeze

  def send_as_visitor(form, answers = ANSWERS, locale: "en", page: nil)
    Current.set(actor: AccessControl::VISITOR, channel: :public) { Forms::Submit.call(form, answers: answers, locale: locale, page: page) }
  end

  def counts = [ Forms::Submission.count, Forms::Delivery.count, Audit::Event.count ]

  def raw_answers(submission)
    Forms::Submission.connection.select_value(Forms::Submission.where(id: submission.id).select(:answers).to_sql)
  end

  test "a valid send writes one encrypted submission and a waiting delivery per destination, and queues a job each after commit" do
    form = forms(:contact)
    second = form.destinations.create!(kind: "mail", position: 1, settings: { "recipients" => "sales@example.com" })
    page = root_page

    result = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      result = send_as_visitor(form, page: page, locale: "en")
      assert_no_enqueued_jobs(only: Forms::DeliveryJob)
    end

    assert result.ok?, result.errors.inspect
    submission = result.record
    assert_kind_of Forms::Submission, submission
    assert_equal [ form, page, "en" ], [ submission.form, submission.page, submission.locale ]
    assert_equal [ "Ada Lovelace", "ada@example.com", "Hello <b>there</b>" ], submission.reload.answers.map { |row| row["value"] }
    assert_equal [ "Your name", "Email address", "Message" ], submission.answers.map { |row| row["label"] }

    raw = raw_answers(submission)
    assert raw.present?
    TYPED.each { |typed| assert_not_includes raw, typed, "the stored column holds no typed text" }

    deliveries = submission.deliveries.order(:id)
    assert_equal [ [ form_destinations(:contact_mail).id, "mail", "waiting" ], [ second.id, "mail", "waiting" ] ],
      deliveries.map { |delivery| [ delivery.destination_id, delivery.kind, delivery.state ] }
    assert_equal MailSettings.current.fingerprint, deliveries.first.queued_fingerprint

    jobs = enqueued_jobs.select { |job| job["job_class"] == "Forms::DeliveryJob" }
    assert_equal deliveries.map { |delivery| [ delivery.to_global_id.to_s ] }, jobs.map { |job| job["arguments"].map { |argument| argument["_aj_globalid"] } }
    TYPED.each { |typed| assert_not_includes jobs.inspect, typed }
  end

  test "invalid answers write nothing and answer INVALID with the field errors and the typed values" do
    before = counts
    result = send_as_visitor(forms(:contact), ANSWERS.merge("f_name0001" => " ", "f_mail0001" => "a@example.com, b@example.com"))

    assert_not result.ok?
    assert_equal [ Forms::Submit::INVALID ], result.errors
    assert_kind_of Forms::Answers::Result, result.record
    assert_equal({ "f_name0001" => :blank, "f_mail0001" => :invalid }, result.record.errors)
    assert_equal "a@example.com, b@example.com", result.record.typed["f_mail0001"]
    assert_equal before, counts
    assert_no_enqueued_jobs
  end

  test "a trashed form answers GONE and writes nothing" do
    form = forms(:contact)
    form.update_columns(trashed_at: Time.current) # version: none (a test puts the form in the trash)
    before = counts

    result = send_as_visitor(form)

    assert_equal [ Forms::Submit::GONE ], result.errors
    assert_equal before, counts
    assert_no_enqueued_jobs
  end

  test "the event is the form's, names the submission by id, holds no answer, no actor row, no IP, and its channel is public" do
    form = forms(:contact)
    result = Current.set(ip_address: "203.0.113.7", request_id: "req-1") { send_as_visitor(form) }
    assert result.ok?

    event = Audit::Event.where(action: "form_submission.received").sole
    assert_equal [ "Forms::Form", form.id, "Contact" ], [ event.subject_type, event.subject_id, event.subject_label ]
    assert_equal({ "submission_id" => result.record.id }, event.metadata)
    assert_nil event.snapshot
    assert_equal({}, event.field_changes)
    assert_equal [ nil, nil, nil ], [ event.actor_type, event.actor_id, event.user_id ]
    assert_equal "visitor", event.actor_label
    assert_nil event.ip, "a visitor's address is never stored"
    assert_equal "public", event.channel
    TYPED.each { |typed| assert_not_includes event.attributes.to_json, typed }
  end

  test "each send is its own event: a visitor's events never coalesce" do
    2.times { assert send_as_visitor(forms(:contact)).ok? }
    assert_equal [ 1, 1 ], Audit::Event.where(action: "form_submission.received").pluck(:occurrences)
  end

  test "without encryption keys the send is UNAVAILABLE, and nothing is written or queued" do
    before = counts
    result = without_encryption_keys { send_as_visitor(forms(:contact)) }

    assert_equal [ Forms::Submit::UNAVAILABLE ], result.errors
    assert_equal before, counts
    assert_no_enqueued_jobs
  end

  test "a submission keeps the labels and choice words it was sent with after the form changes" do
    form = forms(:newsletter)
    sent = send_as_visitor(form, { "f_mail0002" => "bea@example.com", "f_topic002" => "c_news0001", "f_okay0002" => "1" })
    assert sent.ok?, sent.errors.inspect
    assert_empty sent.record.deliveries, "a form with no destination has nothing to deliver"
    assert_no_enqueued_jobs

    changed = as(users(:one)) do
      Forms::Save.call(form, attributes: { name: "Newsletter" }, destinations: [],
        fields: [ { key: "f_topic002", type: "choice", required: false, label: { "en" => "Subject" }, help: {},
                    settings: { display: "dropdown", choices: [ { key: "c_news0001", label: { "en" => "Latest news" } } ] } } ])
    end
    assert changed.ok?, changed.errors.to_sentence

    answers = Forms::Submission.find(sent.record.id).answers
    assert_equal [ [ "Email address", "bea@example.com" ], [ "Topic", "News" ], [ "I agree to receive the newsletter", "Yes" ] ],
      answers.map { |row| [ row["label"], row["display"] ] }
  end

  test "a submission moves no content version" do
    before = PublicSite::Version.current
    assert send_as_visitor(forms(:contact)).ok?
    assert_equal before, PublicSite::Version.current
  end

  test "someone signed in is refused, as anyone who is not the visitor" do
    before = counts
    result = as(users(:reader)) { Forms::Submit.call(forms(:contact), answers: ANSWERS, locale: "en") }
    assert_predicate result, :denied?
    assert_equal before.first(2), counts.first(2)
    assert_equal "forms.submit", Audit::Event.order(:id).last.metadata["permission"]
  end
end
