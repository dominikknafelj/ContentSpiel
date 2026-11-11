module Admin
  module Ui
    # A label in the sans (`text-label`) that says something and cannot be
    # pressed: Default, Built-in, Owner, Unused, No alt, a note's language.
    # A sunken fill and no
    # border: an outline is a button's, or a state chip's (Draft, unpublished
    # changes), never a badge's. `:warn` is No alt's tint; `:accent` is the
    # MCP channel's (`ChannelChipComponent`), the channel a person didn't
    # type on. `size: :compact` is 1px above and below the label where a
    # badge is 2px: the channel chip's, in the audit log's dense rows.
    # Anything else the caller needs on the tag (`data`, `id`) passes through.
    #
    # `mark` is a small sign before the label (a scope chip's type dot),
    # inside the badge and hidden from a screen reader: the label says what
    # the mark shows, so the mark is decoration beside the name.
    class BadgeComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Inline text with no role, named by its label; it takes no focus and cannot be pressed.",
        motion: :none,
        content_edges: %i[short long],
        widths: :fluid,
        interface: %i[label tone size],
        limits: [
          "It cannot be pressed: an outline is a button's or a state chip's, never a badge's.",
          "It draws three tones and two sizes, and another is refused."
        ],
        states: %i[neutral warn accent compact marked],
        keys: [],
        slots: %i[mark],
        controller: nil,
        keyboard: "It takes no focus: a word beside a row's or a card's own link or button, which the keyboard stops on instead; what a caller hands its `mark` slot is a dot, never a control."
      )

      TONES = { neutral: "bg-sunken text-meta", warn: "bg-warn-tint text-warn-ink", accent: "bg-accent-tint text-accent" }.freeze
      CLASS = "inline-flex shrink-0 items-center gap-1 rounded-cs px-1.5 py-0.5 text-label".freeze
      COMPACT_CLASS = "inline-flex shrink-0 items-center gap-1 rounded-cs px-1.5 py-px text-label".freeze
      SIZES = { regular: CLASS, compact: COMPACT_CLASS }.freeze
      MARK_CLASS = "inline-flex".freeze

      renders_one :mark

      def initialize(label:, tone: :neutral, size: :regular, **html)
        raise ArgumentError, "unknown badge tone #{tone.inspect}" unless TONES.key?(tone)
        raise ArgumentError, "unknown badge size #{size.inspect}" unless SIZES.key?(size)

        @label = label
        @tone = tone
        @size = size
        @html = html
      end

      def call
        tag.span(**@html, class: [ SIZES.fetch(@size), TONES.fetch(@tone), @html[:class] ].compact.join(" ")) do
          safe_join([ (tag.span(mark, class: MARK_CLASS, aria: { hidden: true }) if mark?), @label ].compact)
        end
      end
    end
  end
end
