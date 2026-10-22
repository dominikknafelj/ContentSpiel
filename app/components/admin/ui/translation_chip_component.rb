module Admin
  module Ui
    # One language's translation state (design pass spec §4, handoff §2.3 and
    # §9 B14), in the posts list's "Languages" column and each row of the
    # Translations overview. Three cues besides colour: the border (solid,
    # dashed, warn), a mark (a filled `ok` dot, a field-line ring, the ↻ glyph) and an aria-label -- and no red: a
    # missing translation isn't a failure.
    #
    # The glyph alone means nothing to a screen reader, so the chip is
    # `role="img"` with an `aria-label` naming the language and the state, and a
    # `title` for a sighted hover. The language code beside the glyph is visual
    # only, covered by that label. `data-locale` and `data-translation-state`
    # are read by tests and must stay as they were on the old badge.
    class TranslationChipComponent < AdminComponent
      # The mark after the language code (contrast and buttons spec, C1): a
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
          class: "admin-translation-chip inline-flex items-center gap-1 rounded-cs border px-1 font-cs-mono text-label uppercase #{style[:classes]}",
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
