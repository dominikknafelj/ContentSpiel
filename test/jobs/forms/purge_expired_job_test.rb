require "test_helper"

# The daily clean-up of submissions (forms plan, Task 5; decision 6), every
# form's, kept or in the trash, as the trusted nil actor on :system: a form
# that keeps loses what is older than its keeping time (`expired`); one that
# keeps nothing loses what was delivered everywhere and was left behind
# (`delivered`) and, after `Forms::UNDELIVERED_DAYS`, what never was
# (`undelivered`). One form that raises is logged by id and the rest go on.
class Forms::PurgeExpiredJobTest < ActiveJob::TestCase
  include LogCapture

  def submission(form, age:, states: [])
    record = Forms::Submission.create!(form: form, locale: "en", answers: [], created_at: age.ago)
    states.each do |state|
      delivery = record.deliveries.create!(kind: "mail", destination: form.destinations.first)
      delivery.record_sent!(at: Time.current) if state == :sent
      delivery.record_failed!(key: "login", line: nil, at: Time.current) if state == :failed
      delivery.record_failed!(key: Forms::Destinations::Mail::NOT_READY, line: nil, at: Time.current) if state == :not_ready
    end
    record
  end

  def gone?(record) = !Forms::Submission.exists?(record.id)

  def events = Audit::Event.where(action: "form_submissions.deleted").order(:id)

  test "a kept form's submissions older than its days go, newer stay" do
    form = forms(:newsletter)
    old = submission(form, age: 31.days)
    recent = submission(form, age: 29.days)

    Forms::PurgeExpiredJob.perform_now

    assert gone?(old)
    assert_not gone?(recent)
    event = events.last
    assert_equal [ form, "system", nil ], [ event.subject, event.channel, event.user_id ]
    assert_equal({ "count" => 1, "reason" => "expired", "submission_ids" => [ old.id ] }, event.metadata)
  end

  test "a form on the site's default follows a changed default at the next run" do
    form = forms(:newsletter)
    form.update_columns(keep_days: nil)
    SiteSetting.instance.update!(form_keep_days: 90)
    record = submission(form, age: 60.days)

    Forms::PurgeExpiredJob.perform_now
    assert_not gone?(record)

    SiteSetting.instance.update!(form_keep_days: 30)
    Forms::PurgeExpiredJob.perform_now
    assert gone?(record)
  end

  test "a form that does not keep loses its delivered submissions, and its undelivered ones after 30 days" do
    form = forms(:contact)
    delivered = submission(form, age: 1.hour, states: %i[sent])
    failed_recently = submission(form, age: 10.days, states: %i[sent failed])
    waiting = submission(form, age: 1.hour, states: %i[waiting])
    failed_long_ago = submission(form, age: (Forms::UNDELIVERED_DAYS + 1).days, states: %i[failed])

    Forms::PurgeExpiredJob.perform_now

    assert gone?(delivered), "a delivered submission left behind is swept"
    assert_not gone?(failed_recently)
    assert_not gone?(waiting)
    assert gone?(failed_long_ago)
    assert_equal [ [ "delivered", [ delivered.id ] ], [ "undelivered", [ failed_long_ago.id ] ] ],
      events.map { |event| [ event.metadata["reason"], event.metadata["submission_ids"] ] }
  end

  # Forms final review, Important 2: the builder says a form's submissions
  # are sent once mail is set up, so the clean-up does not delete, as
  # undelivered, one that is only waiting for mail while mail is still not
  # set up. Once it is, the plain rule applies again.
  test "while mail is not set up a keep-nothing form's submissions waiting for mail are not swept as undelivered" do
    form = forms(:contact)
    old = (Forms::UNDELIVERED_DAYS + 1).days
    waiting_for_mail = submission(form, age: old, states: %i[not_ready])
    failed_otherwise = submission(form, age: old, states: %i[failed])

    with_mail_state(:not_set_up) { Forms::PurgeExpiredJob.perform_now }
    assert_not gone?(waiting_for_mail), "it waits for mail, as the builder says"
    assert gone?(failed_otherwise), "a mail that failed for another reason still goes after its days"

    with_mail_state(:untested) { Forms::PurgeExpiredJob.perform_now }
    assert gone?(waiting_for_mail), "with mail set up the rule is the plain one"
  end

  test "the delivered ones are decided under a lock on their rows" do
    form = forms(:contact)
    submission(form, age: 1.hour, states: %i[sent])

    statements = capture_sql { Forms::PurgeExpiredJob.perform_now }
    locking = statements.index { |sql| sql.include?("form_submissions") && sql.include?("FOR UPDATE") }
    reading = statements.index { |sql| sql.include?("form_deliveries") && sql.include?("SELECT") }
    assert locking, "the submissions are locked: #{statements.join("\n")}"
    assert reading && reading > locking, "their deliveries are read after the lock"
  end

  # Fix round 1: the sweep decides from the stored setting, never from the
  # keys being there, so a site that lost its keys loses no kept submission
  # before its time, a keeping form with no destination included.
  test "without encryption keys a keeping form is swept by age only" do
    form = forms(:newsletter)
    within = submission(form, age: 29.days)
    delivered = submission(form, age: 1.hour, states: %i[sent])
    stuck = submission(form, age: 29.days, states: %i[failed])
    old = submission(form, age: 31.days)
    assert_empty form.destinations, "the fixture keeps and mails nowhere"

    without_encryption_keys { Forms::PurgeExpiredJob.perform_now }

    assert_not gone?(within)
    assert_not gone?(delivered)
    assert_not gone?(stuck)
    assert gone?(old)
    assert_equal [ "expired" ], events.map { |event| event.metadata["reason"] }
  end

  test "a trashed form's submissions expire too" do
    form = forms(:newsletter)
    Current.set(actor: users(:one)) { assert Trash::Move.call(form).ok? }
    old = submission(form.reload, age: 31.days)

    Forms::PurgeExpiredJob.perform_now

    assert gone?(old)
  end

  test "one form that raises does not stop the others" do
    broken = forms(:contact)
    kept = forms(:newsletter)
    submission(broken, age: 1.hour, states: %i[sent])
    old = submission(kept, age: 31.days)
    original = Forms::DeleteSubmissions.method(:call)

    log = capture_log do
      with_singleton_override(Forms::DeleteSubmissions, :call, lambda { |form, **options|
        raise "a deliberate failure" if form.id == broken.id

        original.call(form, **options)
      }) { Forms::PurgeExpiredJob.perform_now }
    end

    assert gone?(old)
    assert_includes log, "form #{broken.id}"
    assert_not_includes log, "a deliberate failure", "the error's message is not logged: it could quote anything"
  end
end
