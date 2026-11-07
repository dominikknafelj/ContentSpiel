module Admin
  module Ui
    # One scenario per state a list row can show; a live record without
    # changes draws nothing.
    class ListStateComponentPreview < ViewComponent::Preview
      Row = Struct.new(:status, :published_at, :unpublished_changes?)

      def draft = render(Admin::Ui::ListStateComponent.new(record: Row.new("draft", nil, false)))

      def scheduled = render(Admin::Ui::ListStateComponent.new(record: Row.new("scheduled", 2.days.from_now, false)))

      def live = render(Admin::Ui::ListStateComponent.new(record: Row.new("live", 1.day.ago, false)))

      def live_with_changes = render(Admin::Ui::ListStateComponent.new(record: Row.new("live", 1.day.ago, true)))

      def scheduled_with_changes = render(Admin::Ui::ListStateComponent.new(record: Row.new("scheduled", 2.days.from_now, true)))
    end
  end
end
