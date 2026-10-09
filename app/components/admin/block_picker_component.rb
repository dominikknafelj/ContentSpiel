module Admin
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
  # controller (`admin--blocks`). The controller still honours an `after_id`
  # param on `create`, but nothing here sends one.
  class BlockPickerComponent < AdminComponent
    BUTTON_CLASS = [ Admin::ButtonComponent::SMALL_CLASS, Admin::ButtonComponent::VARIANT_CLASSES[:secondary] ].join(" ").freeze

    def initialize(page:, locale:, url_options: {})
      @page = page
      @locale = locale
      @url_options = url_options
    end

    # Container types are left out until the editor can show a section
    # (sections plan, Task 5).
    def types = BlockTypes.all.reject { |type| type.capability?(:container) }

    def create_path = helpers.admin_page_content_blocks_path(page, **url_options)

    def id = "block-picker-end"

    def button_class = BUTTON_CLASS

    private

    attr_reader :page, :locale, :url_options
  end
end
