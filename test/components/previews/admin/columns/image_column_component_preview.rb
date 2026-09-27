module Admin
  module Columns
    class ImageColumnComponentPreview < ViewComponent::Preview
      def empty
        render Admin::Columns::ImageColumnComponent.new(name: "hero_image", value: nil)
      end

      def with_current_image
        page = PreviewFixtures.page(title: "Image column preview")
        page.hero_image.attach(io: StringIO.new("fake image bytes"), filename: "hero.png", content_type: "image/png")

        render Admin::Columns::ImageColumnComponent.new(name: "hero_image", value: page.hero_image)
      end
    end
  end
end
