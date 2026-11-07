module Admin
  module Ui
    # `Admin::Ui::TimeAgoComponent`: each breakpoint.
    class TimeAgoComponentPreview < ViewComponent::Preview
      def just_now = render(Admin::Ui::TimeAgoComponent.new(time: 10.seconds.ago))
      def minutes = render(Admin::Ui::TimeAgoComponent.new(time: 5.minutes.ago))
      def hours = render(Admin::Ui::TimeAgoComponent.new(time: 3.hours.ago))
      def yesterday = render(Admin::Ui::TimeAgoComponent.new(time: Time.zone.yesterday.noon))
      def days = render(Admin::Ui::TimeAgoComponent.new(time: 3.days.ago))
      def this_year = render(Admin::Ui::TimeAgoComponent.new(time: 3.weeks.ago))
      def last_year = render(Admin::Ui::TimeAgoComponent.new(time: 14.months.ago))
      def scheduled = render(Admin::Ui::TimeAgoComponent.new(time: 2.days.from_now))
    end
  end
end
