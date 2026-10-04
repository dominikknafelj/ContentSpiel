module Admin
  # The one button every admin screen renders through -- Save/Cancel in a
  # dialog, "+ Add block", a block card's "Duplicate"/"Delete" menu items,
  # the tree's "+", and so on (spec §4.3). Four variants only: `:primary`
  # (the one emphasized action per screen), `:secondary` (everything else)
  # `:ghost` (a dialog's Cancel) and `:danger` (destructive actions, usually paired with
  # `ConfirmDialogComponent`). Anything else a caller needs on the tag --
  # `data-action` for a Stimulus controller, `disabled`, `form`, a `name`
  # for a `button_to`-style submit -- passes straight through via `**html`
  # rather than this component growing a bespoke keyword per use site.
  class ButtonComponent < AdminComponent
    VARIANT_CLASSES = {
      primary: "bg-accent text-on-accent hover:bg-accent-hover",
      secondary: "border border-line-strong bg-surface text-ink hover:bg-sunken",
      # Solid red: a destructive action's confirm button. `text-white` is the
      # one literal colour the design allows (handoff §9 A1) -- on the red
      # fill white is right in both themes, unlike `on-accent`.
      danger: "bg-danger text-white hover:opacity-90",
      # Dialog Cancel and other low-emphasis actions: no border, no fill.
      ghost: "text-dim hover:bg-sunken hover:text-ink"
    }.freeze

    BASE_CLASS = "inline-flex cursor-pointer items-center justify-center gap-2 rounded-cs px-4 py-2 font-semibold transition-colors disabled:cursor-not-allowed disabled:opacity-50"

    def initialize(label:, variant: :primary, type: "button", **html)
      raise ArgumentError, "unknown button variant #{variant.inspect}" unless VARIANT_CLASSES.key?(variant)

      @label = label
      @variant = variant
      @type = type
      @html = html
    end

    # `**html`'s own `class:`, if given, is appended rather than replacing
    # the variant's classes -- a caller adding e.g. a width utility
    # shouldn't have to also repeat this component's whole class string.
    def html_attrs
      html.merge(type: type, class: [ BASE_CLASS, VARIANT_CLASSES.fetch(variant), html[:class] ].compact.join(" "))
    end

    private

    attr_reader :label, :variant, :type, :html
  end
end
