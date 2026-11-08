module Admin
  module SettingsScreen
    # `GlanceComponent`, the "At a glance" rail, as the compact card it is
    # below the docking width: every row, and what a viewer who manages
    # only the languages sees.
    class GlanceComponentPreview < ViewComponent::Preview
      def all_sections
        render glance(SettingsSections::ALL)
      end

      def languages_only
        render glance(SettingsSections.for { |permission| permission == "languages.manage" })
      end

      private

      def glance(sections)
        site = SiteSetting.instance
        Admin::SettingsScreen::GlanceComponent.new(sections: sections, site_setting: site, mail_settings: MailSettings.current(site, env: {}),
          images_progress: { total: 20, made: 20, failed: 0 }, locales: Locales.enabled, default: Locales.default)
      end
    end
  end
end
