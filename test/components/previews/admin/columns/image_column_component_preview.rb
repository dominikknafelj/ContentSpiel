module Admin
  module Columns
    class ImageColumnComponentPreview < ViewComponent::Preview
      def empty
        render Admin::Columns::ImageColumnComponent.new(name: "hero_image", value: nil)
      end

      def with_current_image
        render Admin::Columns::ImageColumnComponent.new(name: "hero_image", value: PreviewFixtures.media_asset.file)
      end
    end
  end
end
