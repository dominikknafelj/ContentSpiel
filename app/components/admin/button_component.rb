module Admin
  # The one button every admin screen renders through -- Save/Cancel in a
  # dialog, "+ Add block", a block card's "Duplicate"/"Delete" menu items,
  # the tree's "+", and so on (spec §4.3). Five variants only: `:primary`
  # (the one emphasized action per screen), `:secondary` (everything else),
  # `:ghost` (a dialog's Cancel), `:danger_text` (the trigger for a
  # destructive action: a secondary button whose label alone is
  # danger-coloured) and `:danger` (solid red, only for the confirm button
  # inside a `ConfirmDialogComponent`). Anything else a caller needs on the tag --
  # `data-action` for a Stimulus controller, `disabled`, `form`, a `name`
  # for a `button_to`-style submit -- passes straight through via `**html`
  # rather than this component growing a bespoke keyword per use site.
  class ButtonComponent < AdminComponent
    VARIANT_CLASSES = {
      primary: "bg-accent text-on-accent hover:bg-accent-hover",
      secondary: "border border-line-strong bg-surface text-ink hover:bg-sunken",
      # The trigger for a destructive action (round 1's red-outline
      # `:danger_text` is gone, spec §7): a secondary button -- same border,
      # fill and hover -- whose label alone is red, so the one solid red on
      # screen is the confirm button inside the dialog it opens.
      danger_text: "border border-line-strong bg-surface text-danger-ink hover:bg-sunken",
      # Solid red: a dialog's destructive confirm only. `text-white` is the
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
