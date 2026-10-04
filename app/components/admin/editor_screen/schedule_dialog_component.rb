module Admin
  module EditorScreen
    # The Schedule dialog of the editor header (design pass round 2, handoff
    # §10 B21): a date-and-time field read in the SITE time zone, a line that
    # says which zone that is, and -- only when a schedule exists -- "Remove
    # schedule" at the bottom left. It posts to the page's or post's own
    # `schedule` route; a refusal comes back as the controller's
    # `flash[:schedule_error]`, which `HeaderComponent` hands in as `error:` so
    # the dialog reopens (`data-admin--dialog-open-on-load`) with its own
    # message -- a form error is never a toast.
    #
    # The input is `datetime-local` with `min` = now, which steers the native
    # picker, but the form is `novalidate` on purpose: with native validation
    # on, a past time would be stopped by the browser's own bubble and the
    # editor would never see the dialog's one wording ("Pick a time in the
    # future."), which the server enforces anyway. The zone in the line below
    # the field is the zone the server parses the value in (every CS Studio
    # request runs inside `Time.use_zone(site zone)`), so what is shown is what
    # is meant -- the browser's own zone never enters into it.
    #
    # The `<dialog>` is a sibling of the editor header (see `HeaderComponent`),
    # and its buttons live in the dialog's footer, outside the form, so they
    # reach it through `form=`.
    class ScheduleDialogComponent < Admin::AdminComponent
      def initialize(record:, url_options: {}, error: nil)
        raise ArgumentError, "the schedule dialog is for a Page or a Post, not #{record.class}" unless record.is_a?(::Page) || record.is_a?(::Post)

        @record = record
        @url_options = url_options
        @error = error.presence
      end

      # The one place the id is spelled (the header's triggers use it too).
      def self.dialog_id_for(record) = "schedule-#{record.is_a?(::Page) ? "page" : "post"}-#{record.id}"

      def type = record.is_a?(::Page) ? "page" : "post"

      def dialog_id = self.class.dialog_id_for(record)

      def form_id = "#{dialog_id}-form"

      def input_id = "#{dialog_id}-at"

      def error_id = "#{dialog_id}-error"

      def url = helpers.public_send("schedule_admin_#{type}_path", record, **url_options)

      # Only a record that has a schedule can have it removed.
      def scheduled? = record.status == "scheduled"

      def zone = Current.site.effective_time_zone

      # The current schedule, else tomorrow at 09:00 -- both in the site zone.
      def default_time
        @default_time ||= scheduled? ? record.published_at.in_time_zone(zone) : (zone.now + 1.day).change(hour: 9, min: 0)
      end

      def input_value = default_time.strftime(FORMAT)

      def min_value = zone.now.strftime(FORMAT)

      # "Berlin time (GMT+1), the site’s time zone." -- one string (admin copy
      # is one sentence per string). The offset is the one in force at the
      # time shown in the field, so a summer schedule reads GMT+2.
      def zone_line
        "#{zone_name} (#{gmt_offset(default_time.utc_offset)}), the site’s time zone."
      end

      attr_reader :error

      private

      FORMAT = "%Y-%m-%dT%H:%M".freeze

      attr_reader :record, :url_options

      # Rails zone names are city names ("Berlin") or already end in "Time"
      # ("Eastern Time (US & Canada)"); only the former takes " time".
      def zone_name
        zone.name.match?(/time/i) ? zone.name : "#{zone.name} time"
      end

      def gmt_offset(seconds)
        sign = seconds.negative? ? "-" : "+"
        hours, minutes = (seconds.abs / 60).divmod(60)
        "GMT#{sign}#{hours}#{":%02d" % minutes if minutes.positive?}"
      end
    end
  end
end
