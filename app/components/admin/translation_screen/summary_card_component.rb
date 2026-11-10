module Admin
  module TranslationScreen
    # One target language's tile on the Translations screen: its own name in
    # its own language, "% done" (complete items over everything the viewer
    # can read), and its progress (`Admin::Ui::LanguageProgressComponent`: the
    # bar, then "↻ 3 outdated" and "12 missing", or "All translated", as the
    # Dashboard's "Languages behind" panel draws it).
    # `summary` is one entry of `Translations::StateIndex.summaries`: nothing
    # is computed here.
    #
    # The whole tile is one link (`.admin-tile`, an elevation with no border),
    # named for what it does and described by its figures, so a screen reader
    # hears the language, the action and the counts once. The chosen language
    # is the selected tile: the accent outline and `aria-current`.
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

      def percent = Admin::Ui::LanguageProgressComponent.percent(complete: summary[:complete], total: summary[:total])

      def progress
        Admin::Ui::LanguageProgressComponent.new(language: name, counts_id:, **summary.slice(:complete, :total, :outdated, :missing))
      end

      # The ids of the figures that describe the link.
      def done_id = "translation-summary-#{locale}-done"

      def counts_id = "translation-summary-#{locale}-counts"

      private

      attr_reader :locale, :summary
    end
  end
end
