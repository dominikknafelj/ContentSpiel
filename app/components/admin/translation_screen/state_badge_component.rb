module Admin
  module TranslationScreen
    # One language's translation state as a small badge (translation helpers
    # spec §4): ✓ complete, ! missing, ↻ outdated -- the posts list's
    # "Languages" column and each row of the Translations overview.
    #
    # The glyph alone means nothing to a screen reader (and "↻" is read out
    # as "clockwise open circle arrow", if at all), so the badge is
    # `role="img"` with an `aria-label` naming the language and the state in
    # words, and the same words as its `title` for a sighted hover. The
    # language code beside the glyph is visual only, covered by that label.
    class StateBadgeComponent < Admin::AdminComponent
      GLYPHS = { complete: "✓", missing: "!", outdated: "↻" }.freeze

      CLASSES = {
        complete: "border-line text-ok-ink",
        missing: "border-danger bg-danger-tint text-danger-ink",
        outdated: "border-warn bg-warn-tint text-warn-ink"
      }.freeze

      def initialize(state:, locale:)
        @state = state.to_sym
        raise ArgumentError, "unknown translation state #{state.inspect}" unless GLYPHS.key?(@state)

        @locale = locale.to_s
      end

      def call
        tag.span(class: "inline-flex items-center gap-0.5 rounded-cs border px-1 font-cs-mono text-label uppercase #{CLASSES.fetch(state)}",
          role: "img", title: label, aria: { label: label }, data: { locale: locale, translation_state: state }) do
          safe_join([ locale, GLYPHS.fetch(state) ], " ")
        end
      end

      def label = "#{::Locales.name(locale, native: true)}: #{state}"

      private

      attr_reader :state, :locale
    end
  end
end
