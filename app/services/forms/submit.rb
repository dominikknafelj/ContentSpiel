module Forms
  # A visitor's send of a form (forms plan, Task 3; decisions 6 and 8;
  # owner's ruling 2). The endpoint that takes it (`FormSendsController`)
  # calls
  #
  #   Forms::Submit.call(form, answers: params[:answers], locale: "en", page: page, actor: AccessControl::VISITOR)
  #
  # on the channel `:public`, after its spam measures, and answers by the
  # Result: ok (the `Forms::Submission`), or one of three codes as the only
  # error, `INVALID` (the record is the `Forms::Answers::Result`: the field
  # errors and the typed values to draw again), `UNAVAILABLE` (the site has
  # no encryption keys) and `GONE` (the form is in the trash), or `denied?`.
  #
  # THE BENT RULE (decision 8). Every write is a service that authorizes, and
  # a nil or unknown actor on `:public` used to be denied everything. A
  # visitor's send is a write, so it gets an actor of its own:
  # `AccessControl::VISITOR`, allowed `forms.submit` on `:public` and nothing
  # else, on any channel (`AccessControl::Checker`); `forms.submit` is not
  # grantable, so no group, token or user can be given it. Its two guards:
  # test/models/access_control/visitor_test.rb (every registered key on every
  # channel) and test/lib/visitor_actor_test.rb (only the endpoint names the
  # visitor). An owner passes every check, `forms.submit` too, which is
  # harmless: only the endpoint calls this. There is no CSRF token and no
  # session behind the send (a public page carries neither): what makes a
  # forged send harmless is that a send can do nothing but be a submission.
  #
  # NO KEYS, NO ANSWERS (owner's ruling 2). A submission is stored encrypted
  # and nothing else may hold the answers: no sealed copy in a job, no plain
  # row. So without Active Record encryption keys the send is UNAVAILABLE
  # before anything is read or written, and the form says beforehand that
  # it can't take answers (the plan's Task 7).
  #
  # WHAT IS WRITTEN, in one transaction under the form's row lock (so a form
  # trashed or purged meanwhile is answered GONE rather than half-written):
  # the submission (its answers encrypted; labels and displays in the default
  # language as the form says them now, `Forms::Answers`), one `waiting`
  # `Forms::Delivery` per destination of the form, in their order, and the
  # event `form_submission.received` on the form, `snapshot: nil`, metadata
  # the submission's id alone (never the page, the language, a length or an
  # answer), recorded as the visitor: no actor row, no IP (`Audit.record`).
  # After the commit each delivery is queued (`Forms::DeliveryJob`, whose one
  # argument is the delivery's Global ID). Whether the form keeps decides
  # only when the submission goes (`Forms::DeliveryJob`, the clean-up): a
  # submission is a row until every delivery has been sent. Nothing public
  # changes: no content version moves.
  class Submit < ApplicationService
    INVALID = :invalid
    UNAVAILABLE = :unavailable
    GONE = :gone

    def initialize(form, answers:, locale:, page: nil, actor: Current.actor)
      @form = form
      @answers = answers
      @locale = locale.to_s
      @page = page
      @actor = actor
    end

    def call
      return denied("forms.submit", @form) unless authorize!("forms.submit", @form)
      return code(GONE, @form) if @form.trashed?
      return code(UNAVAILABLE, @form) unless Encryption.available?

      cleaned = Answers.clean(@form.fields, @answers, locale: @locale)
      return code(INVALID, cleaned) if cleaned.errors.any?

      submission = nil
      ActiveRecord::Base.transaction do
        # The early answer above came from the copy the caller holds; this
        # one, under the lock, is the one that counts.
        @form.lock!
        raise ActiveRecord::Rollback if @form.trashed?

        submission = Submission.create!(form: @form, page: @page, locale: @locale, answers: cleaned.values)
        @form.destinations.each { |destination| submission.deliveries.create!(destination: destination, kind: destination.kind) }
        record_event("form_submission.received", subject: @form, snapshot: nil, metadata: { "submission_id" => submission.id }, coalesce: false)
      end
      return code(GONE, @form) unless submission

      deliveries = submission.deliveries.to_a
      ActiveRecord.after_all_transactions_commit { deliveries.each { |delivery| DeliveryJob.perform_later(delivery) } }
      success(submission)
    end

    private

    def code(name, record) = Result.failure(record, [ name ])
  end
end
