module RichText
  # `RichText::ImageComponent` (design spec §3.3): with and without a
  # caption, the two states `Blocks::ImageComponentPreview` also covers for
  # the block version. Uses a plain `src:` (the app's own icon, already on
  # disk) rather than a `Media::Asset` -- this component doesn't know what one
  # is (see its own comment) -- so this preview doesn't need
  # `PreviewFixtures` at all.
  class ImageComponentPreview < ViewComponent::Preview
    def with_caption
      render RichText::ImageComponent.new(src: "/icon.png", alt: "A bright, plant-filled room", caption: "A view from the studio")
    end

    def without_caption
      render RichText::ImageComponent.new(src: "/icon.png", alt: "A bright, plant-filled room")
    end
  end
end
