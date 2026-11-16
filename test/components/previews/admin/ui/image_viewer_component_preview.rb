module Admin
  module Ui
    # `Admin::Ui::ImageViewerComponent` at rest: closed and empty, as the
    # admin layout draws it, until a thumbnail opens it. Its script
    # (`admin--ui--image-viewer`) fills it from a pressed
    # `[data-image-viewer-item]` link, which a preview has none of.
    class ImageViewerComponentPreview < ViewComponent::Preview
      def rest
        render(Admin::Ui::ImageViewerComponent.new)
      end
    end
  end
end
