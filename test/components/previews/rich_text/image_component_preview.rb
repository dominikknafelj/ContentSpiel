require_relative "../preview_fixtures"

module RichText
  # `RichText::ImageComponent` (design spec §3.3): with and without a
  # caption, the two states `Blocks::ImageComponentPreview` also covers for
  # the block version. Since media library Task 5 this takes the resolved
  # `Media::Asset` itself, the same as the block version, so this preview
  # needs `PreviewFixtures.media_asset` too.
  class ImageComponentPreview < ViewComponent::Preview
    def with_caption
      render RichText::ImageComponent.new(asset: PreviewFixtures.media_asset, alt_override: "A bright, plant-filled room", caption_override: "A view from the studio")
    end

    def without_caption
      render RichText::ImageComponent.new(asset: PreviewFixtures.media_asset, alt_override: "A bright, plant-filled room")
    end
  end
end
