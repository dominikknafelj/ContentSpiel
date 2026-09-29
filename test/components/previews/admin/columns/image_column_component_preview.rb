module Admin
  module Columns
    # `Admin::Columns::ImageColumnComponent` -- the site logo's upload field
    # (library images use `MediaColumnComponent` instead).
    class ImageColumnComponentPreview < ViewComponent::Preview
      def empty
        render Admin::Columns::ImageColumnComponent.new(name: "logo", value: nil)
      end

      def with_current_image
        render Admin::Columns::ImageColumnComponent.new(name: "logo", value: PreviewFixtures.media_asset.file)
      end
    end
  end
end
