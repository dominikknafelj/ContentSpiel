module Admin
  # `Admin::LanguageSwitcherComponent` (cs-studio spec §6.2): the default mix
  # of enabled locales, and one example with a language missing required
  # translations.
  class LanguageSwitcherComponentPreview < ViewComponent::Preview
    def default
      render Admin::LanguageSwitcherComponent.new(current: "en", url: ->(code) { "?locale=#{code}" })
    end

    def with_missing_translations
      render Admin::LanguageSwitcherComponent.new(current: "en", missing: [ "de" ], url: ->(code) { "?locale=#{code}" })
    end
  end
end
