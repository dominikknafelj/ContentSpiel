module Admin
  module DashboardScreen
    # "Languages behind English": two languages, one still missing items.
    class TranslationPanelComponentPreview < ViewComponent::Preview
      def default
        entries = [
          Dashboard::TranslationNeeds::Entry.new(locale: "de", name: "Deutsch", total: 20, complete: 7, missing: 12, outdated: 1, item: nil),
          Dashboard::TranslationNeeds::Entry.new(locale: "es", name: "Español", total: 20, complete: 20, missing: 0, outdated: 0, item: nil)
        ]
        render Admin::DashboardScreen::TranslationPanelComponent.new(entries:)
      end
    end
  end
end
