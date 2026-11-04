module Admin
  module FormsScreen
    # "Placed on" (design.md 2.7): the pages whose rows hold a Form block of
    # this form (`Forms::Placements`), each its title as a link to its
    # editor; the ones the viewer can't read only as a number. A card with no
    # field, after the form's four cards and before the save bar, so its
    # links are never under the stuck footer; it holds no input, so nothing
    # of it is part of what Save sends.
    class PlacementsComponent < Admin::AdminComponent
      def initialize(placements:, url_options: {})
        @placements = placements
        @url_options = url_options
      end

      private

      attr_reader :placements, :url_options

      def pages = placements.pages

      def hidden = placements.count_hidden

      def title_of(page) = page.title.presence || page.slug.to_s

      def page_path(page) = helpers.admin_page_path(page, **url_options)
    end
  end
end
