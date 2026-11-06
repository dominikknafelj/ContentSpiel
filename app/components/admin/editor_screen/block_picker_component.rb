module Admin
  module EditorScreen
    # The one "+ Add block" at the end of the block list: the area's one primary
    # button, which opens a three-column `Admin::Ui::MenuComponent` of every
    # registered block type, each its icon chip and its name (the menu's keys
    # walk them in reading order, Escape closes it and gives the focus back to
    # the button). A new block is appended; Duplicate
    # (`Admin::ContentBlocksController#duplicate`) is what inserts below a
    # block, and the "⋯" menu and the drag move one. On a page with no blocks
    # this button is all the list shows.
    #
    # Every item is a plain `button_to` POSTing straight to `create`
    # (`Admin::ContentBlocksController#create`) -- Turbo Drive appends
    # `Accept: text/vnd.turbo-stream.html` to every non-GET form submission on
    # its own (no `data-controller`/`data-turbo-stream` needed here), so the
    # controller's Turbo Stream response is applied in place automatically;
    # only the drag/move-up-down side of the block list needs a real Stimulus
    # controller (`admin--editor--blocks`).
    #
    # AT THE END OF A LANE (sections spec §4.2), with `section:` and `column:`,
    # the button is a tertiary "+ Add" (never a second primary in the area)
    # that opens a one-column `Admin::Ui::MenuComponent` of the same items;
    # each also posts `section_id` and `column` -- the controller's own
    # instruction for where the block goes, beside `block[...]`. It offers no
    # container type: a section never holds a section (spec §2.2), and a
    # button whose only answer is a refusal is no offer. Asked of the
    # capability, never of the type's name, so a container type a plugin
    # registers is left out too. The end-of-list menu lists every type: it is
    # where a section is made.
    #
    # Both menus close on the pick (`close_on_select`): the answer puts a card
    # at the end of the list, or a tile into the lane above with the block's
    # form open under the lanes, and a menu left open would lie over them.
    # Both submissions are inside the Blocks section, so `admin--editor--blocks`
    # holds them in the write queue like every add (`holdTurboRequest`).

    class BlockPickerComponent < AdminComponent
      # A menu item's look: the block card's own constant, not a copy of it, so
      # a lane's "+" items and a card's "⋯" items cannot drift apart.
      MENU_ITEM_CLASS = Admin::EditorScreen::BlockCardComponent::MENU_ITEM_CLASS

      def initialize(page:, locale:, url_options: {}, section: nil, column: nil)
        @page = page
        @locale = locale
        @url_options = url_options
        @section = section
        @column = column
      end

      def types = section ? BlockTypes.all.reject { |type| type.capability?(:container) } : BlockTypes.all

      def create_path = helpers.admin_page_content_blocks_path(page, **url_options)

      def id = section ? "block-picker-#{section.id}-#{column}" : "block-picker-end"

      # The trigger is the button component's own string, never one built here
      # (`test/lib/admin_design_rules_test.rb`).
      def end_button_class = Admin::Ui::ButtonComponent.classes(:primary)

      def lane_button_class = Admin::Ui::ButtonComponent.classes(:tertiary, size: :small)

      def menu_item_class = MENU_ITEM_CLASS

      private

      attr_reader :page, :locale, :url_options, :section, :column
    end
  end
end
