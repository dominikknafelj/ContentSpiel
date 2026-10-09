module Admin
  module EditorScreen
    # A section's columns as lanes of tiles (sections spec §4.1, §4.2): one
    # lane per column of the section's layout, left to right, an empty column
    # keeping its place (`BlockOutline#columns`).
    #
    # THE LANE ELEMENT'S DIRECT CHILDREN ARE EXACTLY THE TILES, as the block
    # list's are exactly the cards: a lane's order is its children's order,
    # which is what a move reads and a drag sorts (later tasks of the sections
    # plan; `data-section-id` and `data-column` say which container it is).
    # So the column's label is the lane's sibling inside a wrapper, never its
    # child, and nothing else is ever put into a lane. The "+" that ends each
    # lane (spec §4.2: `Admin::BlockPickerComponent` with the section and the
    # column) is the same: it follows the lane inside the wrapper, so to the
    # eye it is the lane's last line and to a move it is not there. Only for
    # a viewer who may edit, as the "Add block" row is.
    #
    # The label is for the eye and is shown where the lanes are stacked (spec
    # §4.6: a narrow card), where nothing else says which column a tile is in.
    # A screen reader gets the same words from the lane itself, a list with an
    # `aria-label`, at every width -- so the visible label is `aria-hidden`
    # and never read a second time. The width that decides is the card's, in
    # CSS (`.admin-section-lanes`), and the column count reaches the
    # stylesheet as the custom property `--lanes`.
    #
    # The element is `admin--section`'s `lanes` target: it is replaced as a
    # whole when the section's columns change under this screen (`Admin
    # ::ContentBlocksController#section_structure_streams`), and the script
    # then has to say where the focus goes, since the control that was
    # pressed may have been in the lanes that left.
    class SectionLanesComponent < AdminComponent
      def self.lane_id(section, column) = "section-#{section.id}-lane-#{column}"

      def initialize(page:, section:, outline:, locale:, url_options: {}, editable:)
        @page = page
        @section = section
        @outline = outline
        @locale = locale
        @url_options = url_options
        @editable = editable
      end

      def lanes_id = Admin::EditorScreen::SectionCardComponent.lanes_id(section)

      def lane_id(column) = self.class.lane_id(section, column)

      # `[[1, blocks], [2, blocks], ...]`, the column numbers 1-based as stored.
      def lanes = outline.columns(section).each_with_index.map { |blocks, index| [ index + 1, blocks ] }

      def column_label(column) = t(".column", number: column)

      def tile(block)
        Admin::EditorScreen::BlockTileComponent.new(page: page, block: block, locale: locale, url_options: url_options, editable: editable)
      end

      def picker(column)
        Admin::BlockPickerComponent.new(page: page, locale: locale, url_options: url_options, section: section, column: column)
      end

      private

      attr_reader :page, :section, :outline, :locale, :url_options, :editable
    end
  end
end
