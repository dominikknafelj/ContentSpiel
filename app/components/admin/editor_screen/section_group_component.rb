module Admin
  module EditorScreen
    # A section on a translation tab (sections spec §4.5): a plain group -- a
    # heading, then the card of each block it holds, in reading order, column
    # by column (`BlockOutline#blocks_in`). Each card is the block's own form
    # (`Admin::EditorScreen::BlockCardComponent`, `placement: :group`), so every translated
    # field is its pair with the original, autosaved, refused when stale and
    # confirmed as on any card; a view-only viewer gets the same cards
    # disabled, with no autosave (`editable:` is handed down).
    #
    # NOTHING OF THE DEFAULT TAB'S SECTION CARD IS HERE: no lanes, no tiles,
    # no hidden panels, no settings, no `admin--editor--section`. A translator works
    # down the page's text; which column a text stands in is layout, and
    # layout is the same in every language. So the forms are all open, one
    # under the other, in the order the public page is read.
    #
    # THE GROUP STANDS IN THE BLOCK LIST AS THE SECTION'S CARD DOES: a direct
    # child of the list with the section's `dom_id` and `data-block-id`, and a
    # `card` target of `admin--editor--blocks`. The cards around it are still moved
    # from their handles and menus on a translation tab, and the order such a
    # move sends is read from the list's children that carry a
    # `data-block-id` (`admin--editor--blocks#itemsOf`) -- which has to name the
    # section, or the reorder is refused as not listing the page's blocks.
    # It has no handle and no menu of its own, so the section itself is not
    # moved, copied or deleted from this tab: the default-language tab is
    # where structure is edited. `data-container` is the markup's word for
    # "this card holds blocks", as on the section card. The cards inside are
    # the group's children, not the list's, and no `card` targets (`:group`):
    # the list's order never counts them.
    #
    # A section whose type is gone (spec §6) still holds its blocks and they
    # still have translations: it is drawn here like any other, its heading
    # the "Unavailable type" label in place of the name.
    #
    # `first:` and `last:` are the section card's (`SectionCardComponent.for`
    # hands both components the same options); with no Move up or Move down
    # here they say nothing.
    class SectionGroupComponent < AdminComponent
      def initialize(page:, section:, outline:, locale:, url_options: {}, editable: nil, **)
        @page = page
        @section = section
        @outline = outline
        @locale = locale
        @url_options = url_options
        @editable = editable
      end

      def dom_id = ActionView::RecordIdentifier.dom_id(section)

      def editable? = @editable.nil? ? (@editable = can_edit?(page)) : @editable

      def unavailable? = section.definition.nil?

      def heading = unavailable? ? t(".unavailable", type: section.block_type) : t(".heading")

      def blocks = outline.blocks_in(section)

      def card(block)
        Admin::EditorScreen::BlockCardComponent.new(page: page, block: block, locale: locale, url_options: url_options, editable: editable?, placement: :group)
      end

      private

      attr_reader :page, :section, :outline, :locale, :url_options
    end
  end
end
