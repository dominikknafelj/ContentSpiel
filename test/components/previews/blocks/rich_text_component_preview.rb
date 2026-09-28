require_relative "../preview_fixtures"

module Blocks
  # `Blocks::RichTextComponent` (open-types spec §5).
  class RichTextComponentPreview < ViewComponent::Preview
    def default
      page = PreviewFixtures.page(title: "Rich text preview")
      block = page.content_blocks.create!(block_type: :rich_text, position: 0,
        body: PreviewFixtures.rich_doc("This is a sample rich text block, rendered in the same prose styles the public theme uses everywhere else."))

      render Blocks::RichTextComponent.new(block: block, page: page)
    end
  end
end
