module Admin
  module AuditScreen
    # The filter row: untouched, with a custom date range, and about one record.
    class ToolbarComponentPreview < ViewComponent::Preview
      def untouched = toolbar({})
      def custom_range = toolbar(range: "custom", from: "2026-06-01", to: "2026-06-30", channel: "mcp")
      def about_a_record = toolbar(subject_type: "Post", subject_id: "5")

      private

      def toolbar(params)
        filter = Audit::Filter.new(ActiveSupport::HashWithIndifferentAccess.new(params))
        render Admin::AuditScreen::ToolbarComponent.new(filter:, users: User.order(:id).limit(5).to_a)
      end
    end
  end
end
