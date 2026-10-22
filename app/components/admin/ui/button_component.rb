module Admin
  module Ui
    # The one button every admin screen renders through -- Save/Cancel in a
    # dialog, "+ Add block", a block card's "Duplicate"/"Delete" menu items,
    # the tree's "+", and so on (spec §4.3). Five variants only: `:primary`
    # (the one emphasized action per screen), `:secondary` (everything else),
    # `:ghost` (a dialog's Cancel, the editors' Discard changes…), `:danger_text` (the trigger for a
    # destructive action: a secondary button whose label alone is
    # danger-coloured) and `:danger` (solid red, only for the confirm button
    # inside a `Ui::ConfirmDialogComponent`). Anything else a caller needs on the tag --
    # `data-action` for a Stimulus controller, `disabled`, `form`, a `name`
    # for a `button_to`-style submit -- passes straight through via `**html`
    # rather than this component growing a bespoke keyword per use site.
    class ButtonComponent < AdminComponent
      # Every hover is `not-disabled:hover:` (contrast and buttons spec, D1): a
      # disabled button never answers the pointer.
      VARIANT_CLASSES = {
        primary: "border border-transparent bg-accent text-on-accent not-disabled:hover:bg-accent-hover",
        # Outlined in the field line (3:1 on every ground); the pointer turns
        # the outline ink, and nothing else.
        secondary: "border border-field-line bg-surface text-ink not-disabled:hover:border-ink",
        # The trigger for a destructive action (spec §7): a secondary button --
        # same border, fill and hover -- whose label alone is red, so the one
        # solid red on screen is the confirm button inside the dialog it opens.
        danger_text: "border border-field-line bg-surface text-danger-ink not-disabled:hover:border-ink",
        # Solid red: a dialog's destructive confirm only. `text-white` is the
        # one literal colour the design allows (handoff §9 A1) -- on the red
        # fill white is right in both themes, unlike `on-accent`.
        danger: "border border-transparent bg-danger text-white not-disabled:hover:opacity-90",
        # Dialog Cancel, "Discard changes…" and other low-emphasis actions: no visible border, no fill.
        # Primary, danger and ghost carry a transparent 1px border at rest so the
        # disabled look's hairline only recolours it: a button script-toggled
        # disabled (the save bar's Save) never changes size.
        ghost: "border border-transparent text-dim not-disabled:hover:bg-sunken not-disabled:hover:text-ink"
      }.freeze

      # DISABLED is one look for every variant (D1): sunken, meta words, a
      # hairline, no accent and no opacity, so it can't read as a weak
      # primary (disabled is exempt from WCAG 1.4.11; the save bar's line says
      # why it is off). A BUSY button (`admin--ui--busy` sets `aria-busy`) is
      # disabled too but keeps its variant's look beside its spinner.
      COMMON_CLASS = "inline-flex cursor-pointer items-center justify-center gap-2 rounded-cs font-semibold transition-colors " \
                     "disabled:cursor-not-allowed disabled:not-aria-busy:border-line " \
                     "disabled:not-aria-busy:bg-sunken disabled:not-aria-busy:text-meta aria-busy:cursor-progress".freeze

      BASE_CLASS = "#{COMMON_CLASS} px-4 py-2".freeze

      # `size: :small` is the compact button of an inline box (the AI
      # suggestion's Use): the same classes with a tighter padding and a smaller
      # type. Built from `COMMON_CLASS` as whole strings, which Tailwind sees.
      SMALL_CLASS = "#{COMMON_CLASS} px-2 py-0.5 text-sm".freeze

      def initialize(label:, variant: :primary, type: "button", size: :regular, **html)
        raise ArgumentError, "unknown button variant #{variant.inspect}" unless VARIANT_CLASSES.key?(variant)
        raise ArgumentError, "unknown button size #{size.inspect}" unless %i[regular small].include?(size)

        @label = label
        @variant = variant
        @size = size
        @type = type
        @html = html
      end

      # `**html`'s own `class:`, if given, is appended rather than replacing
      # the variant's classes -- a caller adding e.g. a width utility
      # shouldn't have to also repeat this component's whole class string.
      def html_attrs
        html.merge(type: type, class: [ (size == :small ? SMALL_CLASS : BASE_CLASS), VARIANT_CLASSES.fetch(variant), html[:class] ].compact.join(" "))
      end

      private

      attr_reader :label, :variant, :type, :size, :html
    end
  end
end
