module Admin
  module AuditScreen
    # The log's events under day headers (design pass round 3, Task 15):
    # "Today", "Yesterday", "Mon 5 Oct" (with the year when it isn't this one),
    # by the SITE's calendar -- requests run inside the site time zone, so
    # `Time.zone` is its zone and "today" is today where the editors are. An event
    # sits under the day of its LAST moment (`last_occurred_at`, the order the
    # list is in), so a span that crosses midnight is one row, under the day it
    # ended. The headers are drawn per loaded page (round 3 decision D23): a day
    # that carries on across a page boundary has its header at the foot of one
    # page and at the head of the next, once on each.
    #
    # `entries` is `[[event, sentence], ...]` in list order; `event_path` maps an
    # event to the page that opens it (the filters kept).
    class DayListComponent < Admin::AdminComponent
      Day = Data.define(:label, :entries)

      def initialize(entries:, event_path:, today: Time.zone.today)
        @entries = entries
        @event_path = event_path
        @today = today
      end

      def days
        @days ||= @entries.chunk_while { |(a, _), (b, _)| day_of(a) == day_of(b) }.map do |chunk|
          Day.new(label_for(day_of(chunk.first.first)), chunk)
        end
      end

      def path_for(event) = @event_path.call(event)

      private

      def day_of(event) = event.last_occurred_at.in_time_zone.to_date

      def label_for(date)
        return "Today" if date == @today
        return "Yesterday" if date == @today - 1

        date.strftime(date.year == @today.year ? "%a %-d %b" : "%a %-d %b %Y")
      end
    end
  end
end
