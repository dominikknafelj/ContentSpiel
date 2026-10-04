module Admin
  module DashboardScreen
    # A line of "Recent activity": a person (round avatar) and a change made
    # through an API token (the user's own round avatar, "via <name>" and an MCP chip).
    class ActivityRowComponentPreview < ViewComponent::Preview
      def person
        render Admin::DashboardScreen::ActivityRowComponent.new(row: row(via_label: nil))
      end

      def via_api_token
        render Admin::DashboardScreen::ActivityRowComponent.new(row: row(via_label: "Claude desktop"))
      end

      private

      def row(via_label:)
        post = Post.first || Post.new(id: 1, content_type: "blog", title: "A sample post")
        Dashboard::Activity::Row.new(event: Audit::Event.new(channel: via_label ? "mcp" : "admin"), record: post, sentence_parts: [ "published", post, "" ], actor_name: "Dominik",
          via_label:, at: 2.hours.ago, span_end: nil)
      end
    end
  end
end
