require_relative "../preview_fixtures"

module Blocks
  # `Blocks::TableComponent`, its block filled from the type's sample.
  class TableComponentPreview < ViewComponent::Preview
    def default
      page = PreviewFixtures.page(title: "Table preview")
      sample = BlockTypes.fetch(:table).sample
      block = page.content_blocks.create!(block_type: :table, position: 0)
      block.assign_body(RichText::Document.from_markdown(sample.body, tables: true).first.to_h, locale: :en)
      block.caption = sample.translations.fetch("en").fetch(:caption)
      block.save!

      render Blocks::TableComponent.new(block: block, page: page)
    end
  end
end
