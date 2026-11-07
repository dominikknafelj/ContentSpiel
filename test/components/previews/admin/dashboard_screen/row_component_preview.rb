module Admin
  module DashboardScreen
    # A record in "Pick up where you left off" and in "Publishing on its own".
    class RowComponentPreview < ViewComponent::Preview
      def draft
        render Admin::DashboardScreen::RowComponent.new(record: Post.first || Post.new(id: 1, content_type: "blog", title: "A sample post"), variant: :draft)
      end

      def going_live
        post = Post.first || Post.new(id: 1, content_type: "blog", title: "A sample post")
        post.published_at = 5.days.from_now
        render Admin::DashboardScreen::RowComponent.new(record: post, variant: :going_live, mine: true)
      end
    end
  end
end
