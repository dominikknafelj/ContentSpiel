module Admin
  module Ui
    # `Admin::Ui::ScheduledDateComponent`: a scheduled date's amber block,
    # the month over the day.
    class ScheduledDateComponentPreview < ViewComponent::Preview
      def default
        render Admin::Ui::ScheduledDateComponent.new(at: 5.days.from_now)
      end
    end
  end
end
