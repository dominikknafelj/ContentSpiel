module Admin
  module DashboardScreen
    # One of the viewer's drafts in "Pick up where you left off".
    class DraftTileComponentPreview < ViewComponent::Preview
      def post
        render Admin::DashboardScreen::DraftTileComponent.new(record: Post.first || Post.new(id: 1, content_type: "blog", title: "A sample post",
          excerpt: "A first line of what the post is about, and a second one.", updated_at: 2.hours.ago))
      end
    end
  end
end
