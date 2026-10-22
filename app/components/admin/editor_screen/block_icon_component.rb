module Admin
  module EditorScreen
    # A block type's icon where the editor names the type (contrast and
    # buttons spec, C2): 16px dim before the name in the picker, 14px dim
    # between a card's handle and its name, 12px meta before a tile's
    # summary, where it stands in for the name. Decoration: the name is
    # always beside it, on the tile as `sr-only` text. A type that names no
    # icon draws nothing (Ruling 7).
    class BlockIconComponent < AdminComponent
      PLACES = { picker: %w[size-4 text-dim], card: %w[size-3.5 text-dim], tile: %w[size-3 text-meta] }.freeze

      def initialize(definition:, place:)
        raise ArgumentError, "unknown place #{place.inspect}" unless PLACES.key?(place)

        @definition = definition
        @place = place
      end

      def render? = @definition&.icon.present?

      def call
        size, colour = PLACES.fetch(@place)
        # `strip`: the partial's own line breaks would land in a button's text.
        tag.span(helpers.render("admin/shared/icon", name: @definition.icon.to_sym, size: size).strip.html_safe,
          class: "inline-flex shrink-0 #{colour}", aria: { hidden: true }, data: { block_icon: @definition.icon })
      end
    end
  end
end
