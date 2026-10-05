module Admin
  module SettingsScreen
    # `Admin::SettingsScreen::LanguagesCardComponent` and the forms and dialogs
    # of its instant actions (`LanguageDialogsComponent`), round 3, Task 6.
    class LanguagesCardComponentPreview < ViewComponent::Preview
      def default
        site = SiteSetting.instance
        render_with_template(template: "admin/settings_screen/languages_card_component_preview/default", locals: { site: site, values: Admin::SettingsScreen::Values.new(site: site) })
      end

      def typed_order_and_fallback
        site = SiteSetting.instance
        submitted = ActionController::Parameters.new(languages: [ { code: "de", fallback: "en" }, { code: "en" }, { code: "es", fallback: "de" } ]).permit!
        render Admin::SettingsScreen::LanguagesCardComponent.new(site_setting: site, values: Admin::SettingsScreen::Values.new(site: site, submitted: submitted))
      end
    end
  end
end
