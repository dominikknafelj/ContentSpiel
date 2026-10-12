module Admin
  module EditorScreen
    # The dialogs of a published or scheduled record's header (drafts spec
    # §3): "Publish changes" (the overview, now or at a time), "Discard the
    # unpublished changes?" and "Cancel the scheduled change?".
    #
    # DRAWN ONCE, WITH THE PAGE, as siblings after the header, for a record
    # that is not a draft and a viewer who has the right, WHATEVER the record
    # has to publish at that moment: the first save of a clean live page
    # makes "Publish changes…" appear (a mark in the header's chip,
    # `PublishingStateComponent`), and the dialog it opens must be there. No
    # answer to a write replaces any of this, so the three forms here are
    # never taken out of the document: each is sent through
    # `admin--saving--queue-hold`, which holds a press made while a save is
    # out and sends it afterwards, and a form replaced meanwhile would be a
    # press that is lost (docs/reference/save-rule-and-write-queue.md).
    #
    # WHAT IS IN THE PUBLISH DIALOG IS ASKED WHEN IT OPENS: the overview is
    # an empty element the script fills (`admin--editor--publish-dialog`),
    # because what a publish would change is known only then. What is drawn
    # here is what this page view knew: whether a change is scheduled (the
    # "At the scheduled time" choice, "Cancel scheduled change"). In this
    # tab that changes only through a publish, a discard or a cancel, each
    # of which is a full visit; another tab's cancel is answered by the
    # controller ("These changes are no longer scheduled…").
    #
    # A refusal of the publish (a time in the past, the record's own address
    # taken) comes back as `error:` and the dialog reopens with it, the
    # chosen "when" and the typed time (`when_chosen:`, `value:`), as the
    # Schedule dialog does: a form error is never a toast.
    #
    # The date field is `datetime-local`, read in the SITE's time zone, and
    # the form is `novalidate` for the Schedule dialog's reason: the server's
    # one wording is what the editor is shown.
    class PublishChangesDialogComponent < Admin::AdminComponent
      include SiteZoneLine

      FORMAT = "%Y-%m-%dT%H:%M".freeze
      SUBMITTED_FORMAT = /\A\d{4}-\d\d-\d\dT\d\d:\d\d\z/
      WHEN = %w[kept now at].freeze

      def self.kind_of(record) = record.is_a?(::Page) ? "page" : "post"
      def self.dialog_id_for(record) = "publish-changes-#{kind_of(record)}-#{record.id}"
      def self.discard_dialog_id_for(record) = "discard-changes-#{kind_of(record)}-#{record.id}"
      def self.cancel_dialog_id_for(record) = "cancel-scheduled-change-#{kind_of(record)}-#{record.id}"

      def initialize(record:, state: nil, url_options: {}, error: nil, when_chosen: nil, value: nil)
        @record = record
        @state = state
        @url_options = url_options
        @error = error.presence
        @when_chosen = when_chosen
        @submitted_value = value
      end

      def type = self.class.kind_of(record)
      def state = @state ||= ::Publishing::State.of(record)
      def dialog_id = self.class.dialog_id_for(record)
      def discard_dialog_id = self.class.discard_dialog_id_for(record)
      def cancel_dialog_id = self.class.cancel_dialog_id_for(record)
      def form_id = "#{dialog_id}-form"
      def input_id = "#{dialog_id}-at-time"
      def zone_id = "#{dialog_id}-zone"
      def error_id = "#{dialog_id}-error"
      def changes_url = helpers.admin_publishing_changes_path(kind: type, id: record.id, **url_options)
      def publish_url = helpers.admin_publishing_publish_path(kind: type, id: record.id, **url_options)
      def discard_url = helpers.admin_publishing_discard_path(kind: type, id: record.id, **url_options)
      def cancel_url = helpers.admin_publishing_cancel_scheduled_change_path(kind: type, id: record.id, **url_options)

      def may_publish? = can?("#{type}s.publish", record)
      def may_discard? = can_edit?(record)
      # Withdrawing a scheduled change is the state's own action, and needs
      # the right that scheduled it.
      def may_cancel? = state.action?(:cancel_scheduled_change) && may_publish?

      def zone = Current.site.effective_time_zone
      def pending_at = state.pending_at
      def pending_time = I18n.l(pending_at.in_time_zone(zone), format: :"admin.datetime")

      # Which "when" is on: what was chosen before a refusal, else the
      # scheduled time where there is one, else now.
      def chosen
        return @when_chosen if error && WHEN.include?(@when_chosen) && (@when_chosen != "kept" || pending_at)

        pending_at ? "kept" : "now"
      end

      def default_time = @default_time ||= pending_at ? pending_at.in_time_zone(zone) : (zone.now + 1.day).change(hour: 9, min: 0)

      # After a refusal the editor sees what they typed (the Schedule
      # dialog's rule: only the `datetime-local` shape is echoed).
      def input_value
        if error && @submitted_value.is_a?(String)
          return "" if @submitted_value.empty? && @when_chosen == "at"
          return @submitted_value if @submitted_value.match?(SUBMITTED_FORMAT)
        end
        default_time.strftime(FORMAT)
      end

      def min_value = zone.now.strftime(FORMAT)
      def zone_line = site_zone_line(default_time)
      def queue_hold = { turbo_frame: "_top", controller: "admin--saving--queue-hold", action: "submit->admin--saving--queue-hold#submit" }

      attr_reader :error

      private

      attr_reader :record, :url_options
    end
  end
end
