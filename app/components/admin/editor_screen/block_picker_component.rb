module Admin
  module EditorScreen
    # The one "+ Add block" row at the end of the block list (design pass round
    # 2, handoff §4.1): a dashed row with the registered block types as inline
    # buttons. There are no between-cards pickers any more -- a new block is
    # appended and can be moved from its "⋯" menu or dragged, and Duplicate
    # (`Admin::ContentBlocksController#duplicate`) is what inserts below a block.
    # An empty page shows just this row.
    #
    # Every button is a plain `button_to` POSTing straight to `create`
    # (`Admin::ContentBlocksController#create`) -- Turbo Drive appends
    # `Accept: text/vnd.turbo-stream.html` to every non-GET form submission on
    # its own (no `data-controller`/`data-turbo-stream` needed here), so the
    # controller's Turbo Stream response is applied in place automatically;
    # only the drag/move-up-down side of the block list needs a real Stimulus
    # controller (`admin--editor--blocks`). The controller still honours an `after_id`
    # param on `create`, but nothing here sends one.
    #
    # THE SAME PICKER AT THE END OF A LANE (sections spec §4.2), with
    # `section:` and `column:`. A lane is a column wide, so there it is not a
    # row of buttons but a "+" that opens an `Admin::Ui::MenuComponent` of them;
    # each item is the same plain `button_to`, which also posts `section_id`
    # and `column` -- the controller's own instruction for where the block
    # goes, beside `block[...]`, as `after_id` is. Two things differ:
    # - it offers no container type. A section never holds a section (spec
    #   §2.2), and a button whose only answer is a refusal is no offer. Asked
    #   of the capability, never of the type's name, so a container type a
    #   plugin registers is left out too. The end-of-list row lists every
    #   type: it is where a section is made;
    # - the menu closes on the pick (`close_on_select`): its answer puts a
    #   tile into the lane above it and opens the block's form under the lanes,
    #   and a menu left open would lie over both.
    # Both submissions are inside the Blocks section, so `admin--editor--blocks` holds
    # them in the write queue like every add (`holdTurboRequest`).

    class BlockPickerComponent < AdminComponent
      BUTTON_CLASS = [ Admin::Ui::ButtonComponent::SMALL_CLASS, Admin::Ui::ButtonComponent::VARIANT_CLASSES[:secondary] ].join(" ").freeze
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

      def button_class = BUTTON_CLASS

      def menu_item_class = MENU_ITEM_CLASS

      private

      attr_reader :page, :locale, :url_options, :section, :column
    end
  end
end
