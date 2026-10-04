module Admin
  module SettingsScreen
    # `Admin::SettingsScreen::PublishingCardComponent` (round 3, Task 5).
    class PublishingCardComponentPreview < ViewComponent::Preview
      def default
        render Admin::SettingsScreen::PublishingCardComponent.new(values: Admin::SettingsScreen::Values.new(site: SiteSetting.instance))
      end

      def with_error
        submitted = ActionController::Parameters.new(trash_retention_days: "-1").permit!
        render Admin::SettingsScreen::PublishingCardComponent.new(
          values: Admin::SettingsScreen::Values.new(site: SiteSetting.instance, submitted: submitted),
          errors: [ "Trash retention days must be greater than or equal to 0" ]
        )
      end
    end
  end
end
