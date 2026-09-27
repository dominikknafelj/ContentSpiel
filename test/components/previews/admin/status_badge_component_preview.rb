module Admin
  # `Admin::StatusBadgeComponent` (cs-studio spec §4.2): one example per
  # status, `scheduled` with its hover date.
  class StatusBadgeComponentPreview < ViewComponent::Preview
    def draft
      render Admin::StatusBadgeComponent.new(status: "draft")
    end

    def scheduled
      render Admin::StatusBadgeComponent.new(status: "scheduled", at: 1.week.from_now)
    end

    def live
      render Admin::StatusBadgeComponent.new(status: "live")
    end
  end
end
