module Admin
  # `Admin::SettingsFormComponent` (cs-studio spec §6.1, Task 8): the site's
  # own `SiteSetting` singleton, whatever a developer's dev database
  # currently has it set to (`ComponentPreviewsController#discard_preview_
  # writes` keeps this read-only).
  class SettingsFormComponentPreview < ViewComponent::Preview
    def default
      render Admin::SettingsFormComponent.new(site_setting: SiteSetting.instance)
    end
  end
end
