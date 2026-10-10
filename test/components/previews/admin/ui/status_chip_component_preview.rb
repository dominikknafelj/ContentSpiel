module Admin
  module Ui
    # `Admin::Ui::StatusChipComponent` (design pass spec §4): one example per
    # status, `scheduled` with its hover date, and Live hidden as lists show it.
    class StatusChipComponentPreview < ViewComponent::Preview
      def draft
        render Admin::Ui::StatusChipComponent.new(status: "draft")
      end

      def scheduled
        render Admin::Ui::StatusChipComponent.new(status: "scheduled", at: 1.week.from_now)
      end

      def live
        render Admin::Ui::StatusChipComponent.new(status: "live")
      end

      # Renders nothing, on purpose: the posts list, tree and dashboard omit it.
      def live_hidden
        render Admin::Ui::StatusChipComponent.new(status: "live", hide_live: true)
      end
    end
  end
end
