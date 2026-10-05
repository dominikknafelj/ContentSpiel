module Admin
  module TrashScreen
    # `RetentionTagComponent` (round 3, Task 14): in N days, the last day, an
    # overdue item (still TODAY, never negative) and retention off.
    class RetentionTagComponentPreview < ViewComponent::Preview
      def in_days = render(tag(2.days.ago, 30))
      def in_one_day = render(tag(29.days.ago, 30))
      def today = render(tag(30.days.ago, 30))
      def overdue = render(tag(45.days.ago, 30))
      def never = render(tag(45.days.ago, 0))

      private

      def tag(trashed_at, days) = Admin::TrashScreen::RetentionTagComponent.new(trashed_at:, retention_days: days)
    end
  end
end
