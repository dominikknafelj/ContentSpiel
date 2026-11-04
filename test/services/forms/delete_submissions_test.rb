require "test_helper"

# Deleting submissions (forms plan, Task 3): one, several or all of a form's,
# with their deliveries, by an editor with `forms.manage` or by the jobs as
# the trusted actor (the reasons `expired`, `delivered`, `undelivered`).
# One event on the form says how many and why, and never what was in them.
class Forms::DeleteSubmissionsTest < ActiveSupport::TestCase
  setup { Current.actor = users(:one) }

  def submission(form = forms(:newsletter), email: "reader@example.com")
    Forms::Submission.create!(form: form, locale: "en",
      answers: [ { "key" => "f_mail0002", "type" => "email", "label" => "Email address", "value" => email, "display" => email } ])
  end

  def with_delivery(submission)
    submission.deliveries.create!(kind: "mail", destination: form_destinations(:contact_mail))
    submission
  end

  def event = Audit::Event.where(action: "form_submissions.deleted").order(:id).last

  test "one, several or all of a form's submissions are deleted with their deliveries, recorded with the count and the reason and no answer" do
    form = forms(:newsletter)
    first, second, third, fourth = Array.new(4) { |n| with_delivery(submission(email: "person#{n}@example.com")) }
    other = submission(forms(:contact), email: "other@example.com")

    result = Forms::DeleteSubmissions.call(form, ids: [ first.id ])
    assert result.ok?, result.errors.to_sentence
    assert_not Forms::Submission.exists?(first.id)
    assert_equal 0, Forms::Delivery.where(submission_id: first.id).count, "its deliveries go with it"
    assert_equal({ "count" => 1, "reason" => "editor", "submission_ids" => [ first.id ] }, event.metadata)
    assert_equal [ form, users(:one).id, "Newsletter" ], [ event.subject, event.user_id, event.subject_label ]
    assert_nil event.snapshot

    assert Forms::DeleteSubmissions.call(form, ids: [ second.id, third.id, other.id ]).ok?
    assert_equal({ "count" => 2, "reason" => "editor", "submission_ids" => [ second.id, third.id ] }, event.metadata)
    assert Forms::Submission.exists?(other.id), "an id of another form's submission is not this form's to delete"

    assert Forms::DeleteSubmissions.call(form, all: true).ok?
    assert_not Forms::Submission.exists?(fourth.id)
    assert_equal 0, form.submissions.count
    assert Forms::Submission.exists?(other.id)

    Audit::Event.where(action: "form_submissions.deleted").each do |recorded|
      assert_not_includes recorded.attributes.to_json, "@example.com", "no answer is in the event"
    end
  end

  test "submission_ids are in the event only for 50 or fewer" do
    form = forms(:newsletter)
    fifty = Array.new(50) { submission(form) }
    assert Forms::DeleteSubmissions.call(form, ids: fifty.map(&:id)).ok?
    assert_equal fifty.map(&:id).sort, event.metadata["submission_ids"].sort

    Array.new(51) { submission(form) }
    assert Forms::DeleteSubmissions.call(form, all: true, reason: :expired).ok?
    assert_equal({ "count" => 51, "reason" => "expired" }, event.metadata)
  end

  test "the service says which ids it deleted, and none when it deleted nothing" do
    form = forms(:newsletter)
    first, second = Array.new(2) { submission(form) }
    service = Forms::DeleteSubmissions.new(form, all: true)
    assert service.call.ok?
    assert_equal [ first.id, second.id ].sort, service.deleted.sort

    again = Forms::DeleteSubmissions.new(form, all: true)
    assert again.call.ok?
    assert_empty again.deleted
  end

  test "deleting nothing records nothing" do
    before = Audit::Event.count
    result = Forms::DeleteSubmissions.call(forms(:newsletter), ids: [ submission(forms(:contact)).id ])
    assert result.ok?
    assert_equal before, Audit::Event.count
  end

  test "it needs forms.manage, and the jobs delete as the trusted actor" do
    form = forms(:newsletter)
    kept = submission(form)

    result = as(users(:reader)) { Forms::DeleteSubmissions.call(form, all: true) }
    assert_predicate result, :denied?
    assert Forms::Submission.exists?(kept.id)

    Current.actor = nil
    assert Current.set(channel: :system) { Forms::DeleteSubmissions.call(form, ids: [ kept.id ], reason: :delivered) }.ok?
    assert_equal [ "delivered", nil ], [ event.metadata["reason"], event.user_id ]
  end

  test "an unknown reason, and neither ids nor all, are refused before anything" do
    assert_raises(ArgumentError) { Forms::DeleteSubmissions.call(forms(:newsletter), all: true, reason: :bored) }
    assert_raises(ArgumentError) { Forms::DeleteSubmissions.call(forms(:newsletter)) }
  end
end
