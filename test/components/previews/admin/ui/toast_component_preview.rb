module Admin
  module Ui
    # `Admin::Ui::ToastComponent`, one per kind. Each is wrapped in a `#toasts`
    # region so `admin--ui--toast` finds it and the fixed positioning applies.
    class ToastComponentPreview < ViewComponent::Preview
      def success
        render Admin::Ui::ToastRegionComponent.new(flash: { notice: "Saved." })
      end

      def undo
        render Admin::Ui::ToastRegionComponent.new(flash: { notice: "Moved “About” to the trash", undo: { "label" => "Undo", "url" => "#", "method" => "post" } })
      end

      def error
        render Admin::Ui::ToastRegionComponent.new(flash: { alert: "You don't have permission to delete pages" })
      end

      def warning
        render Admin::Ui::ToastComponent.new(message: "This page has unsaved changes.", kind: :warning)
      end
    end
  end
end
