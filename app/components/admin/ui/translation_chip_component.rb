module Admin
  module Ui
    # One language's translation state, in the posts list's "Languages" column and each row of the
    # Translations overview. Three cues besides colour: the border (solid,
    # dashed, warn), a mark (a filled `ok` dot, a field-line ring, the ↻ glyph) and an aria-label -- and no red: a
    # missing translation isn't a failure.
    #
    # The glyph alone means nothing to a screen reader, so the chip is
    # `role="img"` with an `aria-label` naming the language and the state, and a
    # `title` for a sighted hover. The language code beside the glyph is visual
    # only, covered by that label. `data-locale` and `data-translation-state`
    # are read by tests.
    class TranslationChipComponent < AdminComponent
      include Admin::Ui::Contract

      contract(
        accessibility: "An image (role=img) named by its aria-label, the language and its state, with a title for a sighted hover; it takes no focus.",
        motion: :none,
        content_edges: %i[short],
        widths: :fluid,
        interface: %i[state locale],
        limits: [
          "A missing translation is never drawn as a failure: no red.",
          "It draws three states, and another is refused."
        ],
        states: %i[complete missing outdated],
        keys: %w[
          aria_label.complete aria_label.missing aria_label.outdated tooltip.complete tooltip.missing
          tooltip.outdated
        ],
        slots: [],
        controller: nil,
        keyboard: "It takes no focus: an image named by its words, in a row or cell whose own link the keyboard stops on."
      )

      # The mark after the language code: a
      # translated language a filled dot in `ok`, a missing one a 1.5px ring
      # in the field line (3:1, a state mark), an outdated one the ↻ glyph.
      # The chip's own border is decoration. The mark is `aria-hidden`: the
      # chip's `aria-label` says the state.
      STYLES = {
        complete: { classes: "border-line-strong text-ink", mark: "size-[7px] rounded-full bg-ok" },
        missing: { classes: "border-dashed border-line-strong text-meta", mark: "size-[7px] rounded-full border-[1.5px] border-field-line" },
        outdated: { classes: "border-warn text-warn-ink", glyph: "↻" }
      }.freeze

      def initialize(state:, locale:)
        @state = state.to_sym
        raise ArgumentError, "unknown translation state #{state.inspect}" unless STYLES.key?(@state)

        @locale = locale.to_s
      end

      def call
        style = STYLES.fetch(@state)
        mark = style[:mark] && tag.span("", class: "inline-block shrink-0 #{style[:mark]}", aria: { hidden: true }, data: { translation_mark: @state })
        tag.span(safe_join([ @locale, mark || (" #{style[:glyph]}" if style[:glyph]) ].compact),
          class: "admin-translation-chip inline-flex items-center gap-1 rounded-cs border px-1 text-label uppercase #{style[:classes]}",
          role: "img", title: tooltip,
          aria: { label: t(".aria_label.#{@state}", language: ::Locales.name(@locale, native: true)) },
          data: { locale: @locale, translation_state: @state })
      end

      # Outdated names the source language, so the hover says what to compare
      # against; the aria-label stays the short state word.
      def tooltip
        t(".tooltip.#{@state}", language: ::Locales.name(::Translations.primary_locale, native: true))
      end
    end
  end
end
