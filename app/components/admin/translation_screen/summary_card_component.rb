module Admin
  module TranslationScreen
    # One target language's card on the Translations matrix (design pass
    # round 2, Task 18, handoff §4.4): its own name in its own language,
    # "% done" (complete items over everything the viewer can read), a 4px
    # bar and "12 missing · 1 outdated". `summary` is one entry of
    # `Translations::StateIndex.summaries` -- nothing is computed here.
    #
    # Same look and wording as the dashboard's "Needs translation" rows
    # (`Admin::DashboardScreen::TranslationCardComponent`, whose bar widths it
    # shares); translation states are never red, the bar is `ok` on a `line`
    # track and the outdated count reads in `warn-ink`.
    class SummaryCardComponent < Admin::AdminComponent
      def initialize(locale:, summary:)
        @locale = locale.to_s
        @summary = summary
      end

      def name = ::Locales.name(locale, native: true)

      def percent = summary[:total].zero? ? 0 : (summary[:complete] * 100.0 / summary[:total]).round

      def width_class = Admin::DashboardScreen::TranslationCardComponent::WIDTHS[(percent / 5.0).round]

      def counts
        parts = []
        parts << "#{summary[:missing]} missing" if summary[:missing].positive?
        parts << "#{summary[:outdated]} outdated" if summary[:outdated].positive?
        parts.any? ? parts.join(" · ") : "All translated"
      end

      def outdated? = summary[:outdated].positive?

      private

      attr_reader :locale, :summary
    end
  end
end
