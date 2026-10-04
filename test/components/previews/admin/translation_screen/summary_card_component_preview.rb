module Admin
  module TranslationScreen
    # `Admin::TranslationScreen::SummaryCardComponent`: a language part-way and a finished one.
    class SummaryCardComponentPreview < ViewComponent::Preview
      def in_progress
        render Admin::TranslationScreen::SummaryCardComponent.new(locale: "de", summary: { total: 20, complete: 7, missing: 12, outdated: 1 })
      end

      def done
        render Admin::TranslationScreen::SummaryCardComponent.new(locale: "es", summary: { total: 20, complete: 20, missing: 0, outdated: 0 })
      end
    end
  end
end
