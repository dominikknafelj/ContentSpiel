module Admin
  module DashboardScreen
    # A line of "Recent activity": a person (round avatar) and a change made
    # through an API token (square accent avatar).
    class ActivityRowComponentPreview < ViewComponent::Preview
      def person
        render Admin::DashboardScreen::ActivityRowComponent.new(row: row(via_token: false))
      end

      def via_api_token
        render Admin::DashboardScreen::ActivityRowComponent.new(row: row(via_token: true))
      end

      private

      def row(via_token:)
        post = Post.first || Post.new(id: 1, content_type: "blog", title: "A sample post")
        Dashboard::Activity::Row.new(event: nil, record: post, sentence_parts: [ "published", post, "" ], actor_name: "Dominik",
          via_token:, at: 2.hours.ago, span_end: nil)
      end
    end
  end
end
