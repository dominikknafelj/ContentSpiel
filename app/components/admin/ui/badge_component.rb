module Admin
  module Ui
    # A label in the sans (`text-label`) that says something and cannot be
    # pressed: Default, Built-in, Owner, Unused, No alt, a note's language.
    # A sunken fill and no
    # border: an outline is a button's, or a state chip's (Draft, unpublished
    # changes), never a badge's. `:warn` is No alt's tint.
    # Anything else the caller needs on the tag (`data`, `id`) passes through.
    class BadgeComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "Inline text with no role, named by its label; it takes no focus and cannot be pressed.",
        motion: :none,
        content_edges: %i[short long],
        widths: :fluid,
        interface: %i[label tone],
        limits: [
          "It cannot be pressed: an outline is a button's or a state chip's, never a badge's.",
          "It draws two tones, and another is refused."
        ],
        states: %i[neutral warn],
        keys: [],
        slots: [],
        controller: nil
      )

      TONES = { neutral: "bg-sunken text-meta", warn: "bg-warn-tint text-warn-ink" }.freeze
      CLASS = "inline-flex shrink-0 items-center rounded-cs px-1.5 py-0.5 text-label".freeze

      def initialize(label:, tone: :neutral, **html)
        raise ArgumentError, "unknown badge tone #{tone.inspect}" unless TONES.key?(tone)

        @label = label
        @tone = tone
        @html = html
      end

      def call
        tag.span(@label, **@html, class: [ CLASS, TONES.fetch(@tone), @html[:class] ].compact.join(" "))
      end
    end
  end
end
