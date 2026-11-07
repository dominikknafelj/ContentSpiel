module Admin
  module Ui
    # A scheduled date as a status mark: a 40px amber block (`bg-scheduled
    # text-on-scheduled`, the scheduled chip's fill) with the month as a label
    # over the day. It is one of the two places the scheduled fill is drawn,
    # beside `StatusChipComponent` (`admin_design_rules_test`'s
    # `LIVE_SCHEDULED_FILES`), which is why it is a shared status component
    # although only the dashboard draws it.
    #
    # It is hidden from a screen reader: the row it stands in says the date in
    # words in its own `<time>`, so reading the block too would say it twice.
    # The date is read in `Time.zone`, the site's time zone for the request, so
    # the block, the row's phrase and its tooltip agree on the calendar day.
    class ScheduledDateComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Decoration hidden from a screen reader, with no focus: the row it stands in says the date in words.",
        motion: :none,
        content_edges: %i[short],
        widths: :fixed,
        interface: %i[at],
        limits: [
          "It draws a month and a day in the site's time zone, never a time.",
          "It is a status mark and cannot be pressed."
        ],
        states: %i[rest],
        keys: [],
        slots: [],
        controller: nil
      )

      def initialize(at:)
        @at = at
      end

      def call
        local = at.in_time_zone
        tag.span(class: "admin-scheduled-date flex size-10 shrink-0 flex-col items-center justify-center rounded-chip bg-scheduled text-on-scheduled leading-none",
          aria: { hidden: true }) do
          safe_join([
            tag.span(I18n.t("date.abbr_month_names")[local.month], class: "text-label"),
            tag.span(local.day, class: "text-h2 font-semibold")
          ])
        end
      end

      private

      attr_reader :at
    end
  end
end
