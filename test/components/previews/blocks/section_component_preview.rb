require_relative "../preview_fixtures"

module Blocks
  # `Blocks::SectionComponent` (sections spec §5): each of the six layouts
  # as a plain section, then the two bands and the full width. The grid
  # follows the section's own width, so narrowing Lookbook's viewport shows
  # the stacked and the two-by-two states.
  class SectionComponentPreview < ViewComponent::Preview
    def one = render(component(layout: "one"))

    def two = render(component(layout: "two"))

    def three = render(component(layout: "three"))

    def four = render(component(layout: "four"))

    def one_two = render(component(layout: "one_two"))

    def two_one = render(component(layout: "two_one"))

    def tinted = render(component(layout: "two", background: "tinted"))

    def strong = render(component(layout: "three", background: "strong"))

    def strong_full_width = render(component(layout: "one_two", background: "strong", width: "full"))

    # The last column left empty: it keeps its place beside the others.
    def with_an_empty_column = render(component(layout: "three", fill: 2))

    private

    def component(layout:, background: "none", width: "content", fill: nil)
      page = PreviewFixtures.page(title: "Section preview")
      section = page.content_blocks.create!(block_type: :section, position: 0,
        settings: { "layout" => layout, "background" => background, "width" => width })
      (1..(fill || section.column_count)).each do |column|
        page.content_blocks.create!(block_type: :rich_text, section: section, section_column: column, position: 0,
          body: PreviewFixtures.rich_doc("## Column #{column}\n\nA text in a column, with [a link](https://example.com) and a longer line to wrap."))
      end
      page.content_blocks.create!(block_type: :image, section: section, section_column: 1, position: 1,
        caption: "An image in the first column", alt: "The app's icon", media_asset: PreviewFixtures.media_asset)

      Blocks::SectionComponent.new(block: section, page: page.reload)
    end
  end
end
