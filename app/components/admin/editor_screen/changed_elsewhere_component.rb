module Admin
  module EditorScreen
    # The bar an editor sees when a save was REFUSED because the record
    # changed since the form loaded (design pass round 2, handoff §10 B19):
    # "Changed by <name> <time ago>. Your text is still here so you can copy
    # it; reloading shows the latest version." and a Reload link. Put into
    # the header's `#editor-notice` slot by a 409 autosave answer
    # (`Admin::AutosaveResponses#stale_streams`); Reload is a full-page visit
    # (`data-turbo-frame="_top"`), which is what discards the typed text and
    # loads the newer version.
    #
    # Who and when come from the audit log, bounded by the base the refused
    # save carried (`since:`, the `base_updated_at` the form sent): only
    # events AFTER that base can be what made it stale. Without the bound the
    # newest event by someone else could be a change the form had already
    # loaded ("Changed by B 6 minutes ago" when the real change was this same
    # user's save in a second tab). Events are the record's own plus, for a
    # page or post, those of blocks it owns (editing a block is editing its
    # owner), ignoring `access.denied` -- the dashboard's "by" rule
    # (`Dashboard::Feed::NOT_A_CHANGE`).
    #
    # Among those, a change by someone else is preferred, and the newest one
    # is named ("Changed by <name> <time ago>."): a block this editor just
    # saved touches the page too, and "Changed by <you>" would explain
    # nothing. When the only later change is the viewer's own (a second tab or
    # window) it says so, "Changed in another tab or window <time ago>."; with
    # no event after the base at all (a change saved straight through the
    # model), "Changed elsewhere." without a name.
    #
    # `SLACK`: an event is recorded a few milliseconds AFTER the save whose
    # `updated_at` became the base, so the change the form already loaded has
    # an event just past the base. Events within `SLACK` of the base are that
    # one, not a later change.
    #
    class ChangedElsewhereComponent < Admin::AdminComponent
      SLACK = 1.second

      def initialize(record:, reload_url:, since: nil)
        @record = record
        @reload_url = reload_url
        @since = since
      end

      # `{ event:, own: }` for the change to name, or nil.
      def change
        return @change if defined?(@change)

        events = events_after_base
        other = events.where.not(user_id: Current.user&.id).or(events.where(user_id: nil)).first if Current.user
        @change = if other then { event: other, own: false }
        elsif (newest = events.first) then { event: newest, own: Current.user.present? && newest.user_id == Current.user.id }
        end
      end

      private

      attr_reader :record, :reload_url, :since

      def events_after_base
        events = Audit::Event.where.not(action: Dashboard::Feed::NOT_A_CHANGE)
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
    end
  end
end
