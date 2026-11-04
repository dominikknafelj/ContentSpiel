module Forms
  # Deletes submissions of one form, with their deliveries (forms plan, Task
  # 3): those of `ids` that are the form's (an id of another form's is not
  # found here, never deleted), or `all: true` of them. An editor deletes
  # (`reason: :editor`, `forms.manage`, from the submissions list); the jobs
  # delete as the trusted nil actor on `:system`: `:delivered` (a form that
  # keeps nothing, once every delivery was sent, `Forms::DeliveryJob`),
  # `:expired` (the form's keeping time is over) and `:undelivered` (a
  # failed delivery waited `Forms::UNDELIVERED_DAYS`).
  #
  # One event, `form_submissions.deleted`, on the form, `snapshot: nil`,
  # metadata the count, the reason and, for 50 or fewer, the ids
  # (`IDS_IN_EVENT`): never an answer, a label or a language. Deleting
  # nothing (every id gone already, a run with nothing due) records nothing.
  # The deliveries go with their submission (the foreign key cascades).
  class DeleteSubmissions < ApplicationService
    REASONS = %i[editor expired delivered undelivered].freeze
    IDS_IN_EVENT = 50

    # The ids this call deleted, once it has run (empty when it deleted
    # nothing or was refused): what a caller says it deleted, rather than a
    # count it took before the call (a send can land in between).
    attr_reader :deleted

    def initialize(form, ids: nil, all: false, reason: :editor, actor: Current.actor)
      raise ArgumentError, "reason is one of #{REASONS.join(", ")}, not #{reason.inspect}" unless REASONS.include?(reason&.to_sym)
      raise ArgumentError, "name the submissions to delete (ids:) or ask for all: true" if ids.nil? && !all

      @form = form
      @ids = ids
      @all = all
      @reason = reason.to_sym
      @actor = actor
      @deleted = []
    end

    def call
      return denied("forms.manage", @form) unless authorize!("forms.manage", @form)

      ActiveRecord::Base.transaction do
        scope = @form.submissions
        scope = scope.where(id: Array(@ids)) unless @all
        deleted = scope.order(:id).pluck(:id)
        next if deleted.empty?

        Submission.where(id: deleted).delete_all # version: none (a submission is on no public page)
        @deleted = deleted
        metadata = { "count" => deleted.size, "reason" => @reason.to_s }
        metadata["submission_ids"] = deleted if deleted.size <= IDS_IN_EVENT
        record_event("form_submissions.deleted", subject: @form, snapshot: nil, metadata: metadata, coalesce: false)
      end

      success(@form)
    end
  end
end
