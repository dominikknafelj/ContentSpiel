module Admin
  module TranslationScreen
    # One target language's tile on the Translations screen: its own name in
    # its own language, "% done" (complete items over everything the viewer
    # can read), a 4px bar, and how many items are outdated ("↻ 3 outdated",
    # in warn ink) and missing ("12 missing", in meta), or "All translated".
    # `summary` is one entry of `Translations::StateIndex.summaries`: nothing
    # is computed here.
    #
    # The whole tile is one link (`.admin-tile`, an elevation with no border),
    # named for what it does and described by its figures, so a screen reader
    # hears the language, the action and the counts once. The chosen language
    # is the selected tile: the accent outline and `aria-current`.
    #
    # Translation states are never red: the bar is `ok` on a `sunken` track,
    # held at 3:1 by `admin_contrast_test`, and "outdated" carries its ↻ and
    # its word, so the colour is never the only cue.
    class SummaryCardComponent < Admin::AdminComponent
      # `url` is the matrix narrowed to this language (or, for the language
      # already chosen, back to every language); `current` marks that one.
      def initialize(locale:, summary:, url:, current: false)
        @locale = locale.to_s
        @summary = summary
        @url = url
        @current = current
      end

      attr_reader :url

      def current? = @current

      def link_label = t(current? ? ".link_label.all" : ".link_label.language", language: name)

      def name = ::Locales.name(locale, native: true)

      def percent = summary[:total].zero? ? 0 : (summary[:complete] * 100.0 / summary[:total]).round

      def width_class = Admin::DashboardScreen::TranslationPanelComponent::WIDTHS[(percent / 5.0).round]

      def outdated = summary[:outdated]

      def missing = summary[:missing]

      def done? = outdated.zero? && missing.zero?

      # The ids of the figures that describe the link.
      def done_id = "translation-summary-#{locale}-done"

      def counts_id = "translation-summary-#{locale}-counts"

      private

      attr_reader :locale, :summary
    end
  end
end
