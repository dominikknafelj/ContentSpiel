module Admin
  module SettingsScreen
    # `Admin::SettingsScreen::SiteCardComponent` (round 3, Task 5): the default
    # language first, and a translation language first (the original beside
    # each field).
    class SiteCardComponentPreview < ViewComponent::Preview
      def default
        card(Locales.default)
      end

      def in_another_language
        card(Translations.target_locales.first || Locales.default)
      end

      private

      def card(locale)
        site = SiteSetting.instance
        render Admin::SettingsScreen::SiteCardComponent.new(site_setting: site, values: Admin::SettingsScreen::Values.new(site: site), locale: locale)
      end
    end
  end
end
