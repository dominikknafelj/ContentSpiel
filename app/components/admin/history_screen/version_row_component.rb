module Admin
  module HistoryScreen
    # One row of the History screen's versions (the StudioHistory card, "A
    # version row"), from a `Publishing::History::Row`: "Version 7" with its
    # chip, when it went or goes live (and that it was a scheduled change),
    # and who published it, or that it was kept when history began, or that
    # its publisher's account was removed. Its name
    # is the row's one link (`.admin-row-link`, stretched over the row), to
    # the comparison of that version; the chosen row's link is
    # `aria-current="true"`, which the stylesheet draws as the selection
    # (`.admin-history-row`).
    #
    # The chips are the publish states' own (`StatusChipComponent`): Live for
    # the copy on the site, Scheduled for a copy waiting for its time (with
    # its time as the title), none for an earlier one.
    #
    # With `working:` (a `Publishing::History::Working`) it is the first row,
    # the rows as saved now: the unpublished chip while the mark is set and
    # when it was saved. Not a link: a comparison is of a version, and the
    # working version is what each one is compared with.
    class VersionRowComponent < Admin::AdminComponent
      CHIPS = { on_site: "live", scheduled: "scheduled" }.freeze

      def initialize(row: nil, working: nil, href: nil, current: false)
        raise ArgumentError, "a version row draws a version or the working version" unless row.nil? ^ working.nil?

        @row = row
        @working = working
        @href = href
        @current = current
      end

      attr_reader :row, :working, :href

      def working? = working.present?

      def row_key = working? ? "working" : row.number.to_s

      def current? = @current

      def chip_status = CHIPS[row.state]

      # The row's time is `at` (`Publishing::History#shown_at`): a
      # scheduled record's copy in force goes live at the record's time, not
      # when the copy was taken.
      def time_line
        return t(".goes_live", time: datetime(row.at)) if row.at.future?

        # "was scheduled" is said of a copy that has gone live: a pending one
        # is scheduled now, which its chip says.
        line = t(".went_live", time: datetime(row.at))
        row.was_scheduled ? t(".with_scheduled", line: line) : line
      end

      def publisher_name = row.publisher.name_or_email

      # No publisher: the first copy was kept by the migration that began
      # the history, with nobody to name; any other copy's publisher is an
      # account removed since (`created_by_id` nullified).
      def no_publisher_line = t(row.number == 1 ? ".kept_when_began" : ".removed_publisher")

      def saved_line
        saved = local(working.saved_at)
        t(".saved", time: saved.to_date == local(Time.current).to_date ? t(".today", time: I18n.l(saved, format: :"admin.time")) : datetime(working.saved_at))
      end

      private

      def local(time) = time.in_time_zone(Current.site.effective_time_zone)

      def datetime(time) = I18n.l(local(time), format: :"admin.datetime")
    end
  end
end
