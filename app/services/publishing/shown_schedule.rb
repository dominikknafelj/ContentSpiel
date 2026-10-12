module Publishing
  # THE SERVER CHECKS WHAT THE PERSON WAS SHOWN. The publish, discard and
  # cancel dialogs say whether a change is scheduled, and for when; a
  # colleague can schedule one, move it or cancel it between the moment a
  # dialog was filled and the press. So the press carries the pending copy
  # the dialog showed (its id, or nil for none) as `shown_pending:`, and the
  # service, under the record's row lock, refuses with one sentence and
  # writes nothing when that is no longer the pending copy: "Now" never
  # publishes over a schedule the person did not see, "At the scheduled
  # time" never keeps a time that was moved, and a discard never withdraws
  # a scheduled change it did not mention.
  #
  # A caller that showed nothing (a script, the MCP tool, a test) leaves the
  # keyword out and is not checked. An id is enough to tell a moved change:
  # a copy is never updated, so a change with another time is another row.
  #
  # For `PublishChanges`, `DiscardChanges` and `CancelScheduledChange`.
  module ShownSchedule
    NOT_ASKED = Object.new.freeze
    MOVED = "The scheduled change was set, moved or cancelled since this was opened. Nothing was done: look again.".freeze

    private

    def schedule_moved?(record, now)
      return false if @shown_pending.equal?(NOT_ASKED)

      Publishing.pending(record, now: now)&.id != @shown_pending
    end
  end
end
