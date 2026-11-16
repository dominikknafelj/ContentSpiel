require_relative "../preview_fixtures"

module Blocks
  # `Blocks::GalleryComponent`, its block filled from the type's sample.
  class GalleryComponentPreview < ViewComponent::Preview
    def default
      page = PreviewFixtures.page(title: "Gallery preview")
      sample = BlockTypes.fetch(:gallery).sample
      block = page.content_blocks.create!(block_type: :gallery, position: 0)
      block.assign_settings(sample.translations.fetch("en").transform_keys(&:to_s), locale: "en")
      block.save!

      render Blocks::GalleryComponent.new(block: block, page: page)
    end
  end
end
