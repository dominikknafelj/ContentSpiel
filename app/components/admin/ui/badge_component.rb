module Admin
  module Ui
    # A label in the sans (`text-label`) that says something and cannot be
    # pressed: Default, Built-in, Owner, Unused, No alt, a note's language
    # (contrast and buttons spec, D1 and Ruling 13). A sunken fill and no
    # border: an outline is a button's, or a state chip's (Draft, unpublished
    # changes), never a badge's. `:warn` is No alt's tint.
    # Anything else the caller needs on the tag (`data`, `id`) passes through.
    class BadgeComponent < AdminComponent
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
