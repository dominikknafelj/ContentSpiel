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
    # save carried (`since:`, the `base_updated_at` the form sent):
    # `Audit::ChangeSince` is the rule and explains it -- someone else's newest
    # change is named ("Changed by <name> <time ago>."), the viewer's own other
    # tab says so ("Changed in another tab or window <time ago>."), and with no
    # event after the base it is "Changed elsewhere." without a name. The
    # explicit-save screens' banner reads the same class.
    class ChangedElsewhereComponent < Admin::AdminComponent
      SLACK = Audit::ChangeSince::SLACK

      def initialize(record:, reload_url:, since: nil)
        @record = record
        @reload_url = reload_url
        @since = since
      end

      # The `Audit::ChangeSince::Change` to name (`event`, `own`), or nil.
      def change
        return @change if defined?(@change)

        @change = Audit::ChangeSince.for(record, since: since, viewer: Current.user)
      end

      private

      attr_reader :record, :reload_url, :since
    end
  end
end
