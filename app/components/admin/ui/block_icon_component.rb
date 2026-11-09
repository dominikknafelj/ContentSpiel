module Admin
  module Ui
    # A block type's icon wherever CS Studio names the type: on a chip in its
    # family's hue (`Admin::Ui::IconChipComponent`), 24px in the picker and on
    # a card's head, 22px on a tile, where it stands in for the name, and on a
    # section's head, beside the name, and 20px on a Notes for you row, before
    # the words that say where the note is. A type naming no family is on the
    # neutral chip. Decoration: the name is always beside it, on the tile as
    # `sr-only` text, so the chip is hidden from a screen reader. A type that
    # names no icon draws nothing.
    #
    # A TYPE WHOSE ICON FOLLOWS ITS BLOCK (`icon ... for_block:`, the Note
    # block's kind) is drawn with the block's own on its card and its tile,
    # which hand their block in, and with the type's in the picker, which has
    # none. Only such an icon carries an id (`dom_id`): a save's answer
    # replaces it (`Admin::Answers::BlockDrawing#block_icon_streams`), because
    # neither the card's head nor the tile's face is re-rendered by a save.
    class BlockIconComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Decoration hidden from a screen reader: the type's name always stands beside it.",
        motion: :none,
        content_edges: %i[none],
        widths: :fixed_width,
        interface: %i[definition place block],
        limits: [
          "A type that names no icon draws nothing.",
          "Only an icon that follows its block carries an id, and not on a row, where one block can stand twice."
        ],
        states: %i[picker card tile section row],
        keys: [],
        slots: [],
        controller: nil,
        keyboard: [ "test/system/admin/note_inbox_test.rb", "an inbox row is one Tab stop: its avatar, chips and New take no focus" ]
      )

      PLACES = { picker: :regular, card: :regular, tile: :small, section: :small, row: :xsmall }.freeze

      def self.dom_id(block, place) = "block-#{block.id}-icon-#{place}"

      def initialize(definition:, place:, block: nil)
        raise ArgumentError, "unknown place #{place.inspect}" unless PLACES.key?(place)

        @definition = definition
        @place = place
        @block = block
      end

      def render? = icon_name.present?

      def call
        render Admin::Ui::IconChipComponent.new(icon: icon_name, family: @definition.family, size: PLACES.fetch(@place),
          id: (self.class.dom_id(@block, @place) if @block && @place != :row && @definition.icon_follows_block?), data: { block_icon: icon_name })
      end

      private

      # The block's own where the type's icon follows it, else the type's;
      # always a name from `BlockTypeDefinition::ICONS` (`icon_for` raises
      # for any other).
      def icon_name = @icon_name ||= @definition&.icon_for(@block)
    end
  end
end
