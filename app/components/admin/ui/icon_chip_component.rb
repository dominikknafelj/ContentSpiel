module Admin
  module Ui
    # A block type's or a module's icon on a tinted square in the hue of its
    # family (E4, task 7). This is the one place an icon's hue is drawn
    # (`test/lib/admin_design_rules_test.rb`): the pairs are the `--cs-ic-*`
    # tokens, a family's icon on its chip, measured at 3:1 or better on the
    # surface, rail, chrome and popover in both schemes.
    #
    # `family` is a block-type family, `:people`, `:accent` (the tint pair
    # of the secondary button) or `:neutral` (the sunken pair, for a type
    # that names no family). `size` is `:md` (24px) or `:lg` (22px, a tile's
    # and a section's head); the icon is 14px in both.
    #
    # Decoration: a chip always stands beside its type's or module's name,
    # so it is `aria-hidden` and has no words of its own. Anything else the
    # caller needs on the tag (`id`, `data`) passes through.
    class IconChipComponent < AdminComponent
      FAMILIES = {
        text: "bg-ic-text-bg text-ic-text",
        media: "bg-ic-media-bg text-ic-media",
        code: "bg-ic-code-bg text-ic-code",
        form: "bg-ic-form-bg text-ic-form",
        lists: "bg-ic-lists-bg text-ic-lists",
        structure: "bg-ic-structure-bg text-ic-structure",
        people: "bg-ic-people-bg text-ic-people",
        accent: "bg-accent-tint text-accent",
        neutral: "bg-sunken text-dim"
      }.freeze
      SIZES = { md: "size-6", lg: "size-5.5" }.freeze
      CLASS = "inline-flex shrink-0 items-center justify-center rounded-chip".freeze

      def initialize(icon:, family:, size: :md, **html)
        raise ArgumentError, "unknown icon chip family #{family.inspect}" unless FAMILIES.key?(family)
        raise ArgumentError, "unknown icon chip size #{size.inspect}" unless SIZES.key?(size)

        @icon = icon
        @family = family
        @size = size
        @html = html
      end

      def call
        # `strip`: the partial's own line breaks would land in a button's text.
        tag.span(helpers.render("admin/shared/icon", name: @icon.to_sym, size: "size-3.5").strip.html_safe,
          **@html, class: [ CLASS, SIZES.fetch(@size), FAMILIES.fetch(@family), @html[:class] ].compact.join(" "), aria: { hidden: true })
      end
    end
  end
end
