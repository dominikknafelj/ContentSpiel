require_relative "../preview_fixtures"

module Blocks
  # `Blocks::CardComponent`, its block filled from the type's sample.
  class CardComponentPreview < ViewComponent::Preview
    def default
      page = PreviewFixtures.page(title: "Card preview")
      sample = BlockTypes.fetch(:card).sample
      block = page.content_blocks.create!(block_type: :card, position: 0)
      block.assign_settings(sample.translations.fetch("en").transform_keys(&:to_s), locale: "en")
      block.save!

      render Blocks::CardComponent.new(block: block, page: page)
    end
  end
end
