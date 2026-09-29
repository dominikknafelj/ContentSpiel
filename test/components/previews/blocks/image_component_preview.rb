require_relative "../preview_fixtures"

module Blocks
  # `Blocks::ImageComponent` (open-types spec §5): with and without a
  # caption, the two states the old `content_blocks/_image` partial branched
  # on.
  class ImageComponentPreview < ViewComponent::Preview
    def with_caption
      render component(caption: "A view from the studio")
    end

    def without_caption
      render component(caption: "")
    end

    private

    def component(caption:)
      page = PreviewFixtures.page(title: "Image preview")
      block = page.content_blocks.create!(block_type: :image, position: 0, caption: caption, alt: "A bright, plant-filled room",
        media_asset: PreviewFixtures.media_asset)

      Blocks::ImageComponent.new(block: block, page: page)
    end
  end
end
