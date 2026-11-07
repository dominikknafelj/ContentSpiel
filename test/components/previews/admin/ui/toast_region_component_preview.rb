module Admin
  module Ui
    # `Admin::Ui::ToastRegionComponent`: the layout's `#toasts` region, empty
    # and with each kind of flash, and the relay a frame's answer draws (its
    # toasts with no region around them). The region is fixed to the foot of
    # the window, where each example's toast stands.
    class ToastRegionComponentPreview < ViewComponent::Preview
      UNDO = { "label" => "Undo", "url" => "#", "method" => "post" }.freeze

      def empty = render(Admin::Ui::ToastRegionComponent.new(flash: {}))

      def success = render(Admin::Ui::ToastRegionComponent.new(flash: { notice: "Saved." }))

      def undo = render(Admin::Ui::ToastRegionComponent.new(flash: { notice: "Moved “About” to the trash", undo: UNDO }))

      def warning = render(Admin::Ui::ToastRegionComponent.new(flash: { warning: "Moved 2 posts to the trash. 1 was refused: “Launch day”.", undo: UNDO }))

      def error = render(Admin::Ui::ToastRegionComponent.new(flash: { alert: "You don't have permission to delete pages" }))

      def relay = render(Admin::Ui::ToastRegionComponent.new(flash: { notice: "Saved." }, relay: true))
    end
  end
end
