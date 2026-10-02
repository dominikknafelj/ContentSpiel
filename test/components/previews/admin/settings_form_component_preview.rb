module Admin
  # `Admin::SettingsFormComponent` (cs-studio spec §6.1, Task 8): the site's
  # own `SiteSetting` singleton, whatever a developer's dev database
  # currently has it set to (`ComponentPreviewsController#discard_preview_
  # writes` keeps this read-only).
  class SettingsFormComponentPreview < ViewComponent::Preview
    def default
      render Admin::SettingsFormComponent.new(site_setting: SiteSetting.instance)
    end

    # The first language after the default (translation helpers spec §5):
    # the title and tagline in that language, the original beside each.
    def in_another_language
      site = SiteSetting.instance
      locale = (site.locale_codes - [ site.default_locale ]).first || site.default_locale
      render Admin::SettingsFormComponent.new(site_setting: site, locale: locale)
    end
  end
end
