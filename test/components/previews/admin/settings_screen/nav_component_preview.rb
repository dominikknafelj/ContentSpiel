module Admin
  module SettingsScreen
    # `Admin::SettingsScreen::NavComponent`: every section, and what a
    # `languages.manage`-only viewer sees.
    class NavComponentPreview < ViewComponent::Preview
      def all_sections
        render Admin::SettingsScreen::NavComponent.new(sections: SettingsSections::ALL)
      end

      def languages_only
        render Admin::SettingsScreen::NavComponent.new(sections: SettingsSections.for { |permission| permission == "languages.manage" })
      end
    end
  end
end
