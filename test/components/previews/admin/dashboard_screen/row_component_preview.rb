module Admin
  module DashboardScreen
    # A record in "Publishing on its own".
    class RowComponentPreview < ViewComponent::Preview
      def going_live
        post = Post.first || Post.new(id: 1, content_type: "blog", title: "A sample post")
        post.published_at = 5.days.from_now
        render Admin::DashboardScreen::RowComponent.new(record: post, mine: true)
      end
    end
  end
end
