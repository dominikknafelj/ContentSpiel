module Admin
  module Ui
    # A mono label that says something and cannot be pressed: DEFAULT,
    # BUILT-IN, OWNER, UNUSED, NO ALT, a note's language (contrast and
    # buttons spec, D1 and Ruling 13). A sunken fill and no border, so only a
    # button has an outline on a CS Studio screen. `:warn` is NO ALT's tint.
    # Anything else the caller needs on the tag (`data`, `id`) passes through.
    class BadgeComponent < AdminComponent
      TONES = { neutral: "bg-sunken text-meta", warn: "bg-warn-tint text-warn-ink" }.freeze
      CLASS = "inline-flex shrink-0 items-center rounded-cs px-1.5 py-0.5 font-cs-mono text-label uppercase tracking-mono".freeze

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
