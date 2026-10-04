module Admin
  module PostsScreen
    # The posts list's toolbar: search, the All/Live/Drafts/Scheduled control
    # with counts, and the Type / Tag / Translation drop-downs.
    class ToolbarComponentPreview < ViewComponent::Preview
      COUNTS = { "all" => 128, "live" => 96, "drafts" => 20, "scheduled" => 12 }.freeze

      def default
        render Admin::PostsScreen::ToolbarComponent.new(scope: "all", counts: COUNTS, content_types: ContentTypes.all, tags: [],
          filters: { q: nil, type: nil, tag: nil, translation: nil })
      end

      def with_filters
        render Admin::PostsScreen::ToolbarComponent.new(scope: "drafts", counts: COUNTS, content_types: ContentTypes.all, tags: [ Tag.new(name: "rails") ],
          filters: { q: "launch", type: "blog", tag: "rails", translation: "outdated" })
      end
    end
  end
end
