module Admin
  module Ui
    # `Admin::Ui::LanguageProgressComponent`: a language that owes both
    # counts, each alone, a finished one and one with nothing to translate.
    class LanguageProgressComponentPreview < ViewComponent::Preview
      def both = render(Admin::Ui::LanguageProgressComponent.new(language: "Deutsch", complete: 7, total: 20, outdated: 1, missing: 12))

      def outdated = render(Admin::Ui::LanguageProgressComponent.new(language: "Deutsch", complete: 17, total: 20, outdated: 3, missing: 0))

      def missing = render(Admin::Ui::LanguageProgressComponent.new(language: "Español", complete: 8, total: 20, outdated: 0, missing: 12))

      def done = render(Admin::Ui::LanguageProgressComponent.new(language: "Français", complete: 20, total: 20, outdated: 0, missing: 0))

      def empty = render(Admin::Ui::LanguageProgressComponent.new(language: "Deutsch", complete: 0, total: 0, outdated: 0, missing: 0))
    end
  end
end
