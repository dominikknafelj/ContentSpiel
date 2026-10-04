module Admin
  # `Admin::LanguageTabsComponent` (cs-studio spec §6.2): the default mix
  # of enabled locales, and one example with a language missing required
  # translations.
  class LanguageTabsComponentPreview < ViewComponent::Preview
    def default
      render Admin::LanguageTabsComponent.new(current: "en", url: ->(code) { "?locale=#{code}" })
    end

    def with_missing_translations
      render Admin::LanguageTabsComponent.new(current: "en", missing: [ "de" ], url: ->(code) { "?locale=#{code}" })
    end

    def with_overflow
      # Three enabled languages, two visible: the third collapses into "+1".
      render Admin::LanguageTabsComponent.new(current: "en", visible: 2, url: ->(code) { "?locale=#{code}" })
    end

    def with_outdated_translations
      render Admin::LanguageTabsComponent.new(current: "en", missing: [ "es" ], outdated: [ "de" ], url: ->(code) { "?locale=#{code}" })
    end
  end
end
