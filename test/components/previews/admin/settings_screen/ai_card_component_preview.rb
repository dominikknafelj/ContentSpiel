module Admin
  module SettingsScreen
    # `AiCardComponent`, `AiKeyComponent` and `AiTestResultComponent` (round 3, Task 7).
    # The key states are drawn from an unsaved copy of the site row, never from
    # a real key.
    class AiCardComponentPreview < ViewComponent::Preview
      def default
        render Admin::SettingsScreen::AiCardComponent.new(site_setting: SiteSetting.instance, values: Admin::SettingsScreen::Values.new(site: SiteSetting.instance))
      end

      def key_not_set
        render Admin::SettingsScreen::AiKeyComponent.new(site_setting: site(key: nil))
      end

      def key_saved
        render Admin::SettingsScreen::AiKeyComponent.new(site_setting: site(key: "preview-key", saved_at: Time.current))
      end

      def key_saved_without_a_date
        render Admin::SettingsScreen::AiKeyComponent.new(site_setting: site(key: "preview-key"))
      end

      def key_error
        render Admin::SettingsScreen::AiKeyComponent.new(site_setting: site(key: nil), error: "Enter the API key first.")
      end

      def test_connected
        render Admin::SettingsScreen::AiTestResultComponent.new(milliseconds: 412)
      end

      def test_failed
        render Admin::SettingsScreen::AiTestResultComponent.new(message: "The AI provider refused the API key.")
      end

      private

      def site(key:, saved_at: nil)
        SiteSetting.new(time_zone: "UTC").tap { |site| site.ai_api_key = key if key; site.ai_api_key_saved_at = saved_at }
      end
    end
  end
end
