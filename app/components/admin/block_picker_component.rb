module Admin
  # "+ Add block" (cs-studio spec §5.1): a `BlockTypes.all` button list,
  # collapsed behind a small trigger between two existing cards, or shown
  # as the page's own final "+ Add block" call to action at the end of the
  # list (`after_id: nil`) -- the one case every card's own *trailing*
  # picker (`Admin::BlockCardComponent`, rendered for every card but the
  # last) can't cover, since there's no card there to nest it inside of, and
  # is also what an empty page (no blocks yet at all) falls back to
  # entirely on its own.
  #
  # Every button is a plain `button_to` POSTing straight to `create`
  # (`Admin::ContentBlocksController#create`) -- Turbo Drive appends
  # `Accept: text/vnd.turbo-stream.html` to every non-GET form submission on
  # its own (no `data-controller`/`data-turbo-stream` needed here), so the
  # controller's Turbo Stream response is applied in place automatically;
  # only the drag/move-up-down side of the block list needs a real Stimulus
  # controller (`admin--blocks`).
  class BlockPickerComponent < AdminComponent
    def initialize(page:, locale:, url_options: {}, after_id: nil)
      @page = page
      @locale = locale
      @url_options = url_options
      @after_id = after_id
    end

    def types = BlockTypes.all

    def create_path = helpers.admin_page_content_blocks_path(page, **url_options)

    # Between two cards it's the small, collapsed "+" the spec calls for;
    # at the end of the list it's the page's own prominent "+ Add block",
    # open by default so an editor never has to discover a second click
    # just to see what's on offer.
    def between_cards? = after_id.present?

    def trigger_label = between_cards? ? "+" : "+ Add block"

    def id = between_cards? ? "block-picker-after-#{after_id}" : "block-picker-end"

    private

    attr_reader :page, :locale, :url_options, :after_id
  end
end
