module Admin
  module Ui
    # `Admin::Ui::LanguageTabsComponent`: the enabled languages at rest, one
    # missing required translations, one outdated, more languages than fit,
    # and the tabs as buttons.
    class LanguageTabsComponentPreview < ViewComponent::Preview
      def rest
        render Admin::Ui::LanguageTabsComponent.new(current: "en", url: ->(code) { "?locale=#{code}" })
      end

      def missing
        render Admin::Ui::LanguageTabsComponent.new(current: "en", missing: [ "de" ], url: ->(code) { "?locale=#{code}" })
      end

      def overflow
        # Three enabled languages, two visible: the third collapses into "+1".
        render Admin::Ui::LanguageTabsComponent.new(current: "en", visible: 2, url: ->(code) { "?locale=#{code}" })
      end

      def outdated
        render Admin::Ui::LanguageTabsComponent.new(current: "en", missing: [ "es" ], outdated: [ "de" ], url: ->(code) { "?locale=#{code}" })
      end

      # Settings' Site card: every language's fields are on the page, the tabs
      # only switch between them.
      def buttons
        render Admin::Ui::LanguageTabsComponent.new(current: "en", mode: :buttons, missing: [ "es" ], outdated: [ "de" ])
      end
    end
  end
end
