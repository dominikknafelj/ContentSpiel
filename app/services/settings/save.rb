module Settings
  # Saves the site's settings row (`SiteSetting`, the one `Current.site`):
  # CS Studio's Settings screen (`Admin::SettingsController`) and the setup
  # wizard's site and languages steps (`SetupController#update_site`/
  # `#update_languages`) -- which all used to write it straight from the
  # controller (access-control design spec §3.4, "direct writes are
  # removed").
  #
  # `attributes` go through `assign_attributes` as given, so the model's
  # own setters apply: `social_link_rows` normalises the name/URL rows, and
  # `logo` attaches (or, as nil, removes) the file on save.
  #
  # Needs `settings.manage`; one that changes the enabled `locales` too
  # needs `languages.manage`, the right that owns them everywhere else
  # (`Locales::Enable`/`Disable`/`Configure`). The default language stays a
  # settings field, as on the Settings screen. Recorded as
  # `settings.updated`, and only when something actually changed.
  class Save < ApplicationService
    def initialize(site = Current.site, attributes:, actor: Current.actor)
      @site = site
      @attributes = attributes.to_h.symbolize_keys
      @actor = actor
    end

    def call
      return denied("settings.manage", @site) unless authorize!("settings.manage", @site)
      if @attributes.key?(:locales) && !authorize!("languages.manage", @site)
        return denied("languages.manage", @site)
      end

      @site.assign_attributes(@attributes)
      logo_changing = @site.attachment_changes.key?("logo")

      saved = SiteSetting.transaction do
        @site.save || raise(ActiveRecord::Rollback)

        changes = Audit::Snapshot.field_changes_for(@site)
        changes["logo"] = [ nil, @site.logo.attached? ? @site.logo.filename.to_s : nil ] if logo_changing
        record_event("settings.updated", subject: @site, field_changes: changes) if changes.any?
        true
      end
      return failure(@site) unless saved

      success(@site)
    end
  end
end
