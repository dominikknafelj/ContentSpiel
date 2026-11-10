module Admin
  module AuditScreen
    # The log's events in one card, under a band per day: "Today",
    # "Yesterday", "Mon 5 Oct" (with the year when it isn't this one), by the
    # SITE's calendar -- requests run inside the site time zone, so
    # `Time.zone` is its zone and "today" is today where the editors are. An
    # event sits under the day of its LAST moment (`last_occurred_at`, the
    # order the list is in), so a span that crosses midnight is one row,
    # under the day it ended. The bands are drawn per loaded page: a day that
    # carries on across a page boundary has its band at the foot of one page
    # and at the head of the next, once on each.
    #
    # A band is a group row on paper that sticks under the top bar while its
    # day's rows scroll, and gives way to the next day's at the end of its
    # section (the template's comment says why the card allows it).
    #
    # `entries` is `[[event, sentence], ...]` in list order; `event_path` maps an
    # event to the page that opens it (the filters kept).
    class DayListComponent < Admin::AdminComponent
      Day = Data.define(:label, :entries)

      # `isolate`: the card's own stacking context, for the bands' layer. The
      # arbitrary variant rounds the last row's hover ground into the corners.
      CARD_CLASS = "isolate rounded-card bg-surface shadow-1 [&>section:last-child>ul>li:last-child]:rounded-b-card".freeze
      BAND_CLASS = "sticky top-(--admin-top-offset) z-(--cs-z-raised-top) bg-paper px-4 py-1.5 text-label text-meta".freeze

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

      def band_class(index) = index.zero? ? "#{BAND_CLASS} rounded-t-card" : BAND_CLASS

      private

      def day_of(event) = event.last_occurred_at.in_time_zone.to_date

      def label_for(date)
        return t(".today") if date == @today
        return t(".yesterday") if date == @today - 1

        I18n.l(date, format: date.year == @today.year ? :"admin.day" : :"admin.day_with_year")
      end
    end
  end
end
