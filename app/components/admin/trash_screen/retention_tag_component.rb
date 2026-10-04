module Admin
  module TrashScreen
    # When the retention job will delete a trashed item, as a small mono tag
    # (handoff §4.9): "IN 30 DAYS", "IN 1 DAY", "TODAY", or "NEVER" while
    # retention is 0. Never red -- it is a schedule, not a failure.
    #
    # Counted in CALENDAR days of the request's time zone (the site zone,
    # `Admin::BaseController#use_site_time_zone`): the due moment is
    # `trashed_at + retention days`, and the tag says how many dates away
    # that date is. So the last day reads "TODAY" from midnight on, and an
    # item the sweep hasn't reached yet (overdue) reads "TODAY" too, never a
    # negative number. The exact date is the tooltip AND screen-reader text
    # (a visually hidden span), so it isn't hover-only; it names the day,
    # not a time, because the sweep runs on a schedule.
    class RetentionTagComponent < Admin::AdminComponent
      TAG_CLASS = "font-cs-mono text-label uppercase tracking-mono text-meta".freeze

      def initialize(trashed_at:, retention_days:)
        @trashed_at = trashed_at.in_time_zone
        @retention_days = retention_days
      end

      def never? = @retention_days.zero?

      def due_on = (@trashed_at + @retention_days.days).to_date

      def days_left = [ (due_on - Time.zone.today).to_i, 0 ].max

      def label
        return "NEVER" if never?

        days_left.zero? ? "TODAY" : "IN #{days_left} #{days_left == 1 ? "DAY" : "DAYS"}"
      end

      def explanation
        never? ? "Kept until someone deletes it for good" : "Deleted for good on #{due_on.strftime("%-d %b %Y")}"
      end

      def call
        tag.span(data: { retention: "" }, title: explanation, class: TAG_CLASS) do
          safe_join([ label, tag.span(". #{explanation}", class: "sr-only") ])
        end
      end
    end
  end
end
