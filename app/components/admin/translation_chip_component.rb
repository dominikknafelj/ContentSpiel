module Admin
  # One language's translation state (design pass spec §4, handoff §2.3 and
  # §9 B14), in the posts list's "Languages" column and each row of the
  # Translations overview. Three cues besides colour: the border (solid,
  # dashed, warn), a glyph (none, ○, ↻) and an aria-label -- and no red: a
  # missing translation isn't a failure.
  #
  # The glyph alone means nothing to a screen reader, so the chip is
  # `role="img"` with an `aria-label` naming the language and the state, and a
  # `title` for a sighted hover. The language code beside the glyph is visual
  # only, covered by that label. `data-locale` and `data-translation-state`
  # are read by tests and must stay as they were on the old badge.
  class TranslationChipComponent < AdminComponent
    STYLES = {
      complete: { classes: "border-line-strong text-ink", glyph: nil },
      missing: { classes: "border-dashed border-line-strong text-meta", glyph: "○" },
      outdated: { classes: "border-warn text-warn-ink", glyph: "↻" }
    }.freeze

    def initialize(state:, locale:)
      @state = state.to_sym
      raise ArgumentError, "unknown translation state #{state.inspect}" unless STYLES.key?(@state)

      @locale = locale.to_s
    end

    def call
      style = STYLES.fetch(@state)
      tag.span(safe_join([ @locale, style[:glyph] ].compact, " "),
        class: "admin-translation-chip inline-flex items-center gap-0.5 rounded-cs border px-1 font-cs-mono text-[10px] uppercase #{style[:classes]}",
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
