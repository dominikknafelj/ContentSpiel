module Admin
  module DiagramDrawingsScreen
    # A page's part of the Draw diagrams list: its head (the title, the path
    # in the default language, in the sans as every address in CS Studio is
    # (`admin_design_rules_test`, "mono is for code…"), and
    # `ListStateComponent`: Draft, Scheduled, Unpublished changes, nothing
    # for a plain live page), which is no link, over its
    # rows (`RowComponent`). The group carries `data-page-id`, by which the
    # run's script finds the page's title and path for the end-of-run card.
    # A strong rule stands between two pages.
    class PageGroupComponent < Admin::AdminComponent
      def initialize(page:, rows:, language_column:)
        @page = page
        @rows = rows
        @language_column = language_column
      end

      attr_reader :page, :rows

      def title = page.title.presence || t(".untitled")

      def heading_id = "draw-page-#{page.id}"

      def path = PublicSite::Urls.new.path_for(page, ::Locales.default)

      def row_component(row) = RowComponent.new(row:, language_column: @language_column)
    end
  end
end
