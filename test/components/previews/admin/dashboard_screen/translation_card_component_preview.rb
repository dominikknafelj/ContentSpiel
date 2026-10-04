module Admin
  module DashboardScreen
    # "Needs translation": two languages, one with an outdated item to review.
    class TranslationCardComponentPreview < ViewComponent::Preview
      def default
        entries = [
          Dashboard::TranslationNeeds::Entry.new(locale: "de", name: "Deutsch", total: 20, complete: 7, missing: 12, outdated: 1, item: nil),
          Dashboard::TranslationNeeds::Entry.new(locale: "es", name: "Español", total: 20, complete: 20, missing: 0, outdated: 0, item: nil)
        ]
        render Admin::DashboardScreen::TranslationCardComponent.new(entries:)
      end
    end
  end
end
