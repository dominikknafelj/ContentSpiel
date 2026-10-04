module Admin
  module AuditScreen
    # How the audit log writes WHEN, in the site time zone (requests run inside
    # it, so `in_time_zone` is the site's). A coalesced event stands for a span
    # (`occurred_at` .. `last_occurred_at`) and reads "16:05–16:31"; one that
    # crosses midnight names the start's weekday ("Fri 23:50–00:10") so the two
    # ends can't be taken for the same day. The row sits under the day of its
    # LAST moment (the list's order).
    module TimeSpan
      module_function

      def span?(event) = clock(event.occurred_at) != clock(event.last_occurred_at)

      # "16:05" or "16:05–16:31" (the list's time column).
      def short(event)
        return clock(event.last_occurred_at) unless span?(event)

        first = event.occurred_at.in_time_zone
        last = event.last_occurred_at.in_time_zone
        first.to_date == last.to_date ? "#{clock(first)}–#{clock(last)}" : "#{first.strftime("%a %H:%M")}–#{clock(last)}"
      end

      # "Fri 2 Oct 2026, 16:05–16:31 · 12 saves" (the event page's WHEN).
      def long(event)
        first = event.occurred_at.in_time_zone
        last = event.last_occurred_at.in_time_zone
        text =
          if !span?(event) then "#{day(first)}, #{clock(first)}"
          elsif first.to_date == last.to_date then "#{day(first)}, #{clock(first)}–#{clock(last)}"
          else "#{day(first)}, #{clock(first)} – #{day(last)}, #{clock(last)}"
          end
        event.occurrences.to_i > 1 ? "#{text} · #{event.occurrences} saves" : text
      end

      def clock(time) = time.in_time_zone.strftime("%H:%M")

      def day(time) = time.in_time_zone.strftime("%a %-d %b %Y")
    end
  end
end
