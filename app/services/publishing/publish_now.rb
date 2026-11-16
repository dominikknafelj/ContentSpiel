module Publishing
  # "Publish now" on a page or post (D9). On a scheduled record it is a choice:
  #
  # - `with_changes: false` (the default) is what the save services' `published:
  #   true` has always done: the copy taken when it was scheduled goes live now,
  #   and what was typed since stays unpublished changes.
  # - `with_changes: true` also publishes the rows as they are: one copy taken
  #   now from the rows (`PublishChanges`, which withdraws a pending copy, so
  #   the scheduled copy stays as an older version and a change scheduled as
  #   well never goes live), then the save service's `published: true` moves
  #   `published_at` to now.
  #
  # On a record that is not scheduled both are today's publish: there is
  # nothing scheduled to keep apart from the rows. `result.value[:with_changes]`
  # says which was done, for the toast.
  #
  # RIGHTS are the save services' (`publish` on a record that has a
  # `published_at`, `publish` to publish a draft). THE DIALOG: the press may
  # carry the pending copy it showed (`shown_pending:`), checked under the
  # record's row lock as `PublishChanges` does, so "Now" never publishes over a
  # schedule the person did not see (`ShownSchedule`).
  #
  # One transaction, `lock_owner` first (the settings row, then the record's
  # row, as every write of a record's blocks), with the two steps' own
  # `requires_new` transactions inside it: a step that fails rolls back both.
  class PublishNow < ApplicationService
    include ContentBlocks::Structure
    include ShownSchedule

    # authorize: none (the steps' own: `PublishChanges` and the save service check `publish`; a refusal inside the rolled-back transaction is recorded again through `denied`)
    # audit: none (the steps record `changes_published` and `published` themselves)

    def initialize(record, with_changes: false, shown_pending: NOT_ASKED, now: Time.current, actor: Current.actor)
      @record = record
      @with_changes = with_changes
      @shown_pending = shown_pending
      @now = now
      @actor = actor
    end

    def call
      dormant = switched_off_refusal(@record)
      return dormant if dormant

      @outcome = nil
      @record.class.transaction(requires_new: true) do
        lock_owner(@record)
        @record.reload
        abandon(failure(@record, [ MOVED ])) if schedule_moved?(@record, Time.current)

        scheduled = @record.status == "scheduled"
        taking = @with_changes && scheduled
        if taking && (Publishing.pending(@record) || !Changes.of(@record).none?)
          # `at: now` also gives a change that is only scheduled the time it
          # is published for now (`PublishChanges`).
          published = PublishChanges.call(@record, at: @now)
          abandon(published) unless published.ok?

          @record.reload
        end

        saved = service.call(@record, attributes: { published: true })
        abandon(saved) unless saved.ok?

        @outcome = success(saved.record, value: { with_changes: taking })
      end
      # A step's `access.denied` went with the rollback above: written again,
      # once, outside it.
      return denied(@outcome.permission, @record) if @outcome.denied?

      @outcome
    end

    private

    # A failed step answers with its own result and takes the other step's
    # write back with it.
    def abandon(result)
      @outcome = result
      raise ActiveRecord::Rollback
    end

    def service = @record.is_a?(Page) ? Pages::Save : Posts::Save
  end
end
