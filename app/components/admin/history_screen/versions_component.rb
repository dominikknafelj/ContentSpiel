module Admin
  module HistoryScreen
    # The History screen's versions (the StudioHistory card, "The screen" and
    # "Empty and narrow"): the working version, then a page of copies newest
    # first (`Publishing::History`, 50 to a page), each a `VersionRowComponent`
    # linking to its comparison, and the pager at the foot.
    #
    # ONE ELEMENT, TWO LOOKS, and no script: a `<details>` that is the lists'
    # rail (`.admin-list-rail__rail`) where the list's container docks it, and
    # below that a disclosure above the comparison, closed, whose summary
    # names the chosen version. Docked, the stylesheet forces its content
    # visible and hides the summary (`.admin-history-versions`,
    # `::details-content`), so the rows are never drawn twice. A row is a
    # link to another address, so choosing one "closes" the disclosure: the
    # answer draws it closed again.
    #
    # `url` builds a row's address from a version's number, `page_url` a
    # page's of the pager; both keep the comparison's other choices.
    class VersionsComponent < Admin::AdminComponent
      def initialize(history:, chosen:, url:, page_url:)
        @history = history
        @chosen = chosen
        @url = url
        @page_url = page_url
      end

      attr_reader :history, :chosen

      def rows = history.rows

      def row_url(row) = @url.call(row.number)

      def page_url = @page_url

      def pagination = history.pagination

      def chosen?(row) = chosen && row.number == chosen.number

      def summary_title = chosen ? t(".version", number: chosen.number) : t(".heading")

      def summary_line
        count = t(".count", count: pagination.total)
        return count unless chosen

        time = I18n.l(chosen.live_at.in_time_zone(Current.site.effective_time_zone).to_date, format: :"admin.short_with_year")
        t(".summary_line", time: t(chosen.live_at.future? ? ".goes_live" : ".went_live", time: time), count: count)
      end
    end
  end
end
