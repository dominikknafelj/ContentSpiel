module Admin
  module Ui
    # The one button every admin screen renders through -- Save/Cancel in a
    # dialog, "+ Add block", a block card's "Duplicate"/"Delete" menu items,
    # the tree's "+", and so on (spec §4.3). Five variants only: `:primary`
    # (the one emphasized action per screen: a solid accent fill raised to
    # shadow 2), `:secondary` (everything else: an accent tint, accent words,
    # no outline), `:tertiary` (accent words, no fill: a dialog's Cancel;
    # `:ghost` is no variant and raises), `:danger_text` (the trigger for a
    # destructive action: sunken, with danger-coloured words, because red
    # words on the violet tint would fight)
    # and `:danger` (solid red, only for the confirm button inside a
    # `Ui::ConfirmDialogComponent`). Anything else a caller needs on the tag --
    # `data-action` for a Stimulus controller, `disabled`, `form`, a `name`
    # for a `button_to`-style submit -- passes straight through via `**html`
    # rather than this component growing a bespoke keyword per use site.
    #
    # The whole look is in this file and nowhere else: `VARIANT_CLASSES` and
    # `COMMON_CLASS`, joined by `.classes(variant, size:)`, which is also what
    # the setup wizard's links (`SetupHelper`) are drawn with. The variant a
    # caller asks for is the one place to move a button's look: a button that
    # throws work away (Discard changes…) is `:danger_text`.
    class ButtonComponent < AdminComponent
      # Every hover is `not-disabled:hover:` (contrast and buttons spec, D1): a
      # disabled button never answers the pointer.
      VARIANT_CLASSES = {
        primary: "bg-accent text-on-accent shadow-2 not-disabled:hover:bg-accent-hover not-disabled:hover:shadow-3 " \
                 "not-disabled:active:translate-y-px not-disabled:active:shadow-none",
        # The design draws no hover for it: the lift to shadow 1 is the
        # only change, so a secondary never moves or changes colour.
        secondary: "bg-accent-tint text-accent not-disabled:hover:shadow-1",
        tertiary: "bg-transparent text-accent not-disabled:hover:underline",
        # Solid red: a dialog's destructive confirm only. `on-danger` is the
        # token for the words on it (white in light, near-black in dark).
        danger: "bg-danger text-on-danger not-disabled:hover:opacity-90",
        # The trigger for a destructive action (spec §7): sunken, red words.
        danger_text: "bg-sunken text-danger-ink not-disabled:hover:shadow-1"
      }.freeze

      # Every variant carries `border border-transparent` at rest, so that no
      # state changes the size (a button script-toggled disabled, the save
      # bar's Save). DISABLED is one look for every variant (D1): sunken, meta
      # words, no shadow, no hairline and no opacity, so it can't read as a
      # weak primary. A BUSY button (`admin--ui--busy` sets `aria-busy`) is
      # disabled too but keeps its variant's look beside its spinner.
      COMMON_CLASS = "inline-flex cursor-pointer items-center justify-center gap-2 rounded-button border border-transparent font-semibold transition-colors " \
                     "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent " \
                     "disabled:cursor-not-allowed disabled:not-aria-busy:bg-sunken disabled:not-aria-busy:text-meta " \
                     "disabled:not-aria-busy:shadow-none aria-busy:cursor-progress".freeze

      BASE_CLASS = "#{COMMON_CLASS} px-4 py-2".freeze

      # `size: :small` is the compact button of an inline box (the AI
      # suggestion's Use): the same classes with a tighter padding, a smaller
      # type and the smaller radius. Whole strings, which Tailwind sees.
      SMALL_CLASS = "#{COMMON_CLASS.sub('rounded-button', 'rounded-button-sm')} px-2 py-0.5 text-sm".freeze

      # What a button is drawn with, as one string: the component's own tag and
      # the wizard's links (`SetupHelper`) both call it.
      def self.classes(variant, size: :regular)
        VARIANT_CLASSES.fetch(variant) { raise ArgumentError, "unknown button variant #{variant.inspect}" }
        raise ArgumentError, "unknown button size #{size.inspect}" unless %i[regular small].include?(size)

        [ (size == :small ? SMALL_CLASS : BASE_CLASS), VARIANT_CLASSES.fetch(variant) ].join(" ")
      end

      # `icon:` (a name of the shared icon partial, `admin/shared/icon`) makes
      # an ICON BUTTON: the icon is all it shows, and `label` is its name, as
      # its `aria-label` and as the shared tooltip's text
      # (`Admin::Ui::TooltipComponent`), so a mouse reads what a screen
      # reader hears. The tooltip's controller and actions come before the
      # caller's own `data: { controller:, action: }`, which are kept.
      def initialize(label:, variant: :primary, type: "button", size: :regular, icon: nil, **html)
        raise ArgumentError, "unknown button variant #{variant.inspect}" unless VARIANT_CLASSES.key?(variant)
        raise ArgumentError, "unknown button size #{size.inspect}" unless %i[regular small].include?(size)

        @label = label
        @variant = variant
        @size = size
        @type = type
        @icon = icon
        @html = html
      end

      # `**html`'s own `class:`, if given, is appended rather than replacing
      # the variant's classes -- a caller adding e.g. a width utility
      # shouldn't have to also repeat this component's whole class string.
      def html_attrs
        attrs = html.merge(type: type, class: [ self.class.classes(variant, size: size), (TooltipComponent::HOST if icon), html[:class] ].compact.join(" "))
        return attrs unless icon

        tooltip = TooltipComponent.host_data
        data = html.fetch(:data, {})
        attrs.merge(aria: html.fetch(:aria, {}).merge(label: label),
          data: data.merge(controller: [ tooltip[:controller], data[:controller] ].compact.join(" "), action: [ tooltip[:action], data[:action] ].compact.join(" ")))
      end

      private

      attr_reader :label, :variant, :type, :size, :icon, :html

      def icon_content
        safe_join([ helpers.render("admin/shared/icon", name: icon, size: "size-4").strip.html_safe, render(TooltipComponent.new(text: label)) ])
      end
    end
  end
end
