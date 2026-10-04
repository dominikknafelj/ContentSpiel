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
    # Who and when is the record's newest audit event -- for a page or post
    # also any event about a block it owns, since editing a block is editing
    # its owner -- ignoring `access.denied`, exactly the rule the dashboard
    # uses for "by" (`Dashboard::Feed::NOT_A_CHANGE`, `#last_change`), so the
    # two can never name different people. This is one record, so two small
    # queries rather than the dashboard's batched LATERAL join. A change with
    # no event at all (saved straight through the model) reads "Changed
    # elsewhere." without a name; an event with no user is "System".
    class ChangedElsewhereComponent < Admin::AdminComponent
      def initialize(record:, reload_url:)
        @record = record
        @reload_url = reload_url
      end

      def change
        return @change if defined?(@change)

        @change = newest_event
      end

      private

      attr_reader :record, :reload_url

      def newest_event
        events = Audit::Event.where.not(action: Dashboard::Feed::NOT_A_CHANGE)
        own = events.where(subject_type: record.class.base_class.name, subject_id: record.id)
        scope = if record.is_a?(::Page) || record.is_a?(::Post)
          via_blocks = events.where(subject_type: ContentBlock.base_class.name,
            subject_id: ContentBlock.where(owner_type: record.class.base_class.name, owner_id: record.id).select(:id))
          own.or(via_blocks)
        else
          own
        end

        newest = scope.includes(:user).order(last_occurred_at: :desc, id: :desc)
        # The change that made THIS editor's base stale is someone else's: a
        # block this editor has just saved touches the page too (their own
        # newest event), but "Changed by <you>" would be no explanation.
        # So the newest event by anyone else is preferred, and only when
        # there is none (the same person in another tab, or a change with no
        # user) is the newest event itself named.
        (Current.user && newest.where.not(user_id: Current.user.id).or(newest.where(user_id: nil)).first) || newest.first
      end
    end
  end
end
