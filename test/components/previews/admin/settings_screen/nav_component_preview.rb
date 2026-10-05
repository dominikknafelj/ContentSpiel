module Admin
  module SettingsScreen
    # `Admin::SettingsScreen::NavComponent` (round 3, Task 5): everything, and
    # what a `languages.manage`-only viewer sees.
    class NavComponentPreview < ViewComponent::Preview
      def all_sections
        render Admin::SettingsScreen::NavComponent.new(sections: Admin::SettingsScreen::NavComponent::SECTIONS)
      end

      def languages_only
        render Admin::SettingsScreen::NavComponent.new(sections: Admin::SettingsScreen::NavComponent::SECTIONS.select { |s| s[:id] == "languages" })
      end
    end
  end
end
