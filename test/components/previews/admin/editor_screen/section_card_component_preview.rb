module Admin
  module EditorScreen
    # `Admin::EditorScreen::SectionCardComponent` (sections spec §4.1–§4.3):
    # a three-column section with a text in its first column, an image
    # without an image in its second (a tile that needs attention) and an
    # empty third lane. The forms are in the markup but hidden: a tile opens
    # one only where `admin--editor--section` runs. `narrow` puts the same card in a
    # column too narrow for the lanes to sit side by side, where they stack
    # with their column labels (spec §4.6).
    class SectionCardComponentPreview < ViewComponent::Preview
      def three_columns
        render section_card
      end

      def narrow
        render_with_template locals: { card: section_card }
      end

      private

      def section_card
        page = PreviewFixtures.page(title: "Section preview")
        section = page.content_blocks.create!(block_type: "section", position: 0, settings: { "layout" => "three" })
        page.content_blocks.create!(block_type: "rich_text", section: section, section_column: 1, position: 0,
          body: PreviewFixtures.rich_doc("A text in the first column of a section."))
        page.content_blocks.create!(block_type: "image", section: section, section_column: 2, position: 0)

        outline = BlockOutline.new(page.content_blocks.reload)
        Admin::EditorScreen::SectionCardComponent.new(page: page, section: outline.top_level.first, outline: outline, locale: "en")
      end
    end
  end
end
