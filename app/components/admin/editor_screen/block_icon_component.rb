module Admin
  module EditorScreen
    # A block type's icon where the editor names the type (contrast and
    # buttons spec, C2): 16px dim before the name in the picker, 14px dim
    # between a card's handle and its name, 12px meta before a tile's
    # summary, where it stands in for the name. Decoration: the name is
    # always beside it, on the tile as `sr-only` text. A type that names no
    # icon draws nothing (Ruling 7).
    #
    # A TYPE WHOSE ICON FOLLOWS ITS BLOCK (`icon ... for_block:`, the Note
    # block's kind; note block plan, ruling 12) is drawn with the block's own
    # on its card and its tile, which hand their block in, and with the
    # type's in the picker, which has none. Only such an icon carries an id
    # (`dom_id`): a save's answer replaces it
    # (`Admin::ContentBlocksController#block_icon_streams`), because neither
    # the card's head nor the tile's face is re-rendered by a save.
    class BlockIconComponent < AdminComponent
      PLACES = { picker: %w[size-4 text-dim], card: %w[size-3.5 text-dim], tile: %w[size-3 text-meta] }.freeze

      def self.dom_id(block, place) = "#{Admin::EditorScreen::BlockCardComponent.error_prefix(block)}-icon-#{place}"

      def initialize(definition:, place:, block: nil)
        raise ArgumentError, "unknown place #{place.inspect}" unless PLACES.key?(place)

        @definition = definition
        @place = place
        @block = block
      end

      def render? = icon_name.present?

      def call
        size, colour = PLACES.fetch(@place)
        # `strip`: the partial's own line breaks would land in a button's text.
        tag.span(helpers.render("admin/shared/icon", name: icon_name.to_sym, size: size).strip.html_safe,
          id: (self.class.dom_id(@block, @place) if @block && @definition.icon_follows_block?),
          class: "inline-flex shrink-0 #{colour}", aria: { hidden: true }, data: { block_icon: icon_name })
      end

      private

      # The block's own where the type's icon follows it, else the type's;
      # always a name from `BlockTypeDefinition::ICONS` (`icon_for` raises
      # for any other).
      def icon_name = @icon_name ||= @definition&.icon_for(@block)
    end
  end
end
