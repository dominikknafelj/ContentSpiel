module Admin
  # `Admin::ToastComponent`, one per kind. Each is wrapped in a `#toasts`
  # region so `admin--toast` finds it and the fixed positioning applies.
  class ToastComponentPreview < ViewComponent::Preview
    def success
      render Admin::ToastRegionComponent.new(flash: { notice: "Saved." })
    end

    def undo
      render Admin::ToastRegionComponent.new(flash: { notice: "Moved “About” to the trash", undo: { "label" => "Undo", "url" => "#", "method" => "post" } })
    end

    def error
      render Admin::ToastRegionComponent.new(flash: { alert: "You don't have permission to delete pages" })
    end

    def warning
      render Admin::ToastComponent.new(message: "This page has unsaved changes.", kind: :warning)
    end
  end
end
