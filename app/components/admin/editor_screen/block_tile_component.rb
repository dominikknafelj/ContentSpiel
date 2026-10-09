module Admin
  module EditorScreen
    # A block inside a section, as it stands in its column (sections spec
    # §4.2): its type and one line of its content, on a button that opens the
    # block's form under the lanes (`admin--section#toggle`).
    #
    # THE TILE HAS THE BLOCK'S `dom_id`, as a card of the block list has: it
    # is the element that stands for the block where the block is, the one a
    # lane's order is read from and a delete removes. The form is elsewhere
    # -- `Admin::BlockCardComponent`'s `placement: :panel`, under its own
    # `panel_id` -- and the face names it with `aria-controls`.
    #
    # The face is a real button, so a tile is opened by Enter and Space and
    # is in the Tab order; `aria-expanded` says whether its form is the open
    # one and is kept by `admin--section`. `open:` is for a tile rendered
    # while its form is to be shown at once (a block just added): the script
    # opens the panel, and the tile must not say "collapsed" in between.
    #
    # `page:`, `url_options:` and `editable:` are what the tile's own controls
    # will need (a grip, a menu: later tasks of the sections plan). Today the
    # tile has none, and a viewer who can't edit may still open it: the form
    # they get is the disabled one a view-only card shows.
    class BlockTileComponent < AdminComponent
      def initialize(page:, block:, locale:, url_options: {}, editable:, open: false)
        @page = page
        @block = block
        @locale = locale
        @url_options = url_options
        @editable = editable
        @open = open
      end

      def dom_id = ActionView::RecordIdentifier.dom_id(block)

      def label = block.definition&.label || block.block_type

      def panel_id = Admin::BlockCardComponent.panel_id(block)

      def open? = @open

      private

      attr_reader :page, :block, :locale, :url_options
    end
  end
end
