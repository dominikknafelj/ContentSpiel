module Audit
  # Who changed `record` after a form loaded it, for the notice a refused stale
  # save shows: the editors' "Changed by <name> <time ago>."
  # (`Admin::EditorScreen::ChangedElsewhereComponent`) and the banner of the
  # explicit-save screens (`admin/shared/_stale_banner`, `Admin::StaleForm`).
  # One rule for both, so the two can't name different people.
  #
  # Who and when come from the audit log, bounded by the base the refused save
  # carried (`since:`, the `base_updated_at` the form sent): only events AFTER
  # that base can be what made it stale. Without the bound the newest event by
  # someone else could be a change the form had already loaded ("Changed by B
  # 6 minutes ago" when the real change was this same user's save in a second
  # tab). Events are the record's own plus, for a page or post, those of blocks
  # it owns (editing a block is editing its owner), ignoring `access.denied` --
  # the dashboard's "by" rule (`Dashboard::Feed::NOT_A_CHANGE`).
  #
  # Among those, a change by someone else is preferred, and the newest one is
  # the answer (`own: false`): a block this editor just saved touches the page
  # too, and "Changed by <you>" would explain nothing. When the only later
  # change is the viewer's own (a second tab or window) that one is the answer,
  # `own: true`; with no event after the base at all, nil -- a change saved
  # straight through the model, or one whose event names ANOTHER record: a
  # group's `updated_at` also moves when a user's editor changes its members
  # (the event is the user's), and a user's when a group's editor does, so
  # those read as the plain "changed elsewhere", never as the wrong name.
  #
  # `SLACK`: an event is recorded a few milliseconds AFTER the save whose
  # `updated_at` became the base, so the change the form already loaded has an
  # event just past the base. Events within `SLACK` of the base are that one,
  # not a later change.
  #
  # It answers data only (the event, whose `user`/`user_id` and
  # `last_occurred_at` the caller draws through `Admin::UserNameComponent` and
  # `Admin::TimeAgoComponent`), and takes the viewer as an argument rather
  # than reading `Current`.
  class ChangeSince
    SLACK = 1.second

    Change = Data.define(:event, :own)

    # A `Change`, or nil. `since` nil means no bound (the newest change at all).
    def self.for(record, since:, viewer:)
      events = events_for(record, since)
      other = events.where.not(user_id: viewer.id).or(events.where(user_id: nil)).first if viewer
      if other then Change.new(event: other, own: false)
      elsif (newest = events.first) then Change.new(event: newest, own: viewer.present? && newest.user_id == viewer.id)
      end
    end

    def self.events_for(record, since)
      # A sign-in or sign-out is recorded with the user as its subject but changes
      # nothing the form shows ("This user was changed by B just now" for B signing
      # in after an admin put B in a group); no other subject type has such events.
      events = Audit::Event.where.not(action: Dashboard::Feed::NOT_A_CHANGE).where.not("audit_events.action LIKE 'session.%'")
      events = events.where("audit_events.last_occurred_at > ?", since + SLACK) if since
      own = events.where(subject_type: record.class.base_class.name, subject_id: record.id)
      scope = if record.is_a?(::Page) || record.is_a?(::Post)
        via_blocks = events.where(subject_type: ContentBlock.base_class.name,
          subject_id: ContentBlock.where(owner_type: record.class.base_class.name, owner_id: record.id).select(:id))
        own.or(via_blocks)
      else
        own
      end

      scope.includes(:user).order(last_occurred_at: :desc, id: :desc)
    end
    private_class_method :events_for
  end
end
