module Admin
  module TranslationScreen
    # `Admin::TranslationScreen::SummaryCardComponent`: a language part-way,
    # the chosen language, and a finished one.
    class SummaryCardComponentPreview < ViewComponent::Preview
      def in_progress
        render Admin::TranslationScreen::SummaryCardComponent.new(locale: "de", summary: { total: 20, complete: 7, missing: 12, outdated: 1 }, url: "#de")
      end

      def current
        render Admin::TranslationScreen::SummaryCardComponent.new(locale: "de", summary: { total: 20, complete: 7, missing: 12, outdated: 1 }, url: "#all", current: true)
      end

      def done
        render Admin::TranslationScreen::SummaryCardComponent.new(locale: "es", summary: { total: 20, complete: 20, missing: 0, outdated: 0 }, url: "#es")
      end
    end
  end
end
