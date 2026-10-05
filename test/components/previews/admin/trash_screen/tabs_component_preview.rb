module Admin
  module TrashScreen
    # `TabsComponent` (round 3, Task 14): All is the sum; an empty type reads 0.
    class TabsComponentPreview < ViewComponent::Preview
      COUNTS = { "page" => 2, "post" => 12, "media" => 0 }.freeze

      def all = render(tabs(nil))
      def pages = render(tabs("pages"))
      def images_empty = render(tabs("images"))

      private

      def tabs(current) = Admin::TrashScreen::TabsComponent.new(counts: COUNTS, current:, url: ->(key) { "#?type=#{key}" })
    end
  end
end
