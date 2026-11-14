require_relative "../preview_fixtures"

module Blocks
  # `Blocks::DiagramComponent`, its block filled from the type's sample.
  class DiagramComponentPreview < ViewComponent::Preview
    def default
      page = PreviewFixtures.page(title: "Diagram preview")
      sample = BlockTypes.fetch(:diagram).sample.translations.fetch("en")
      block = page.content_blocks.create!(block_type: :diagram, position: 0, caption: sample[:caption])
      block.assign_settings(sample.slice(:source, :drawing, :description).transform_keys(&:to_s), locale: "en")
      block.save!

      render Blocks::DiagramComponent.new(block: block, page: page)
    end
  end
end
