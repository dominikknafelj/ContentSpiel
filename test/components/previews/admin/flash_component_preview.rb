module Admin
  # `Admin::FlashComponent`: a notice, an alert, and a notice with its
  # one-click follow-up (the trash's Undo).
  class FlashComponentPreview < ViewComponent::Preview
    def notice
      render Admin::FlashComponent.new(notice: "Restored “About”", alert: nil)
    end

    def alert
      render Admin::FlashComponent.new(notice: nil, alert: "You don't have permission to delete pages")
    end

    def notice_with_action
      render Admin::FlashComponent.new(notice: "Moved “About” to the trash", alert: nil,
        action: { label: "Undo", url: "#", method: :post })
    end
  end
end
