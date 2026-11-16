require_relative "../preview_fixtures"

module Blocks
  # `Blocks::GalleryComponent` in its two layouts, its block filled from the
  # type's sample (three library images, a label, captions and an alt
  # override). The carousel's controls stay hidden here: its script is a
  # public page's, and Lookbook's layout does not load it.
  class GalleryComponentPreview < ViewComponent::Preview
    def grid
      render component("grid")
    end

    def carousel
      render component("carousel")
    end

    private

    def component(layout)
      page = PreviewFixtures.page(title: "Gallery preview")
      definition = BlockTypes.fetch(:gallery)
      images = Array.new(definition.sample.images) { PreviewFixtures.media_asset }
      attributes, = ContentModel::SampleBlock.arguments(definition, default: "en", locales: [ "en" ], settings: { "layout" => layout },
        media_asset_ids: images.map(&:id))
      block = page.content_blocks.new(block_type: :gallery, position: 0)
      block.assign_settings(attributes[:settings], locale: "en")
      block.save!

      Blocks::GalleryComponent.new(block: block, page: page)
    end
  end
end
