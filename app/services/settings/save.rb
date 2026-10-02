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
  # `translations` carries the translated title and tagline (translation
  # helpers spec §5), `{ locale => { title:, tagline: } }` -- the same shape
  # as `Pages::Save`/`Media::Save`'s, each locale assigned inside its own
  # `Mobility.with_locale`, and anything but `TRANSLATED` ignored. The
  # default language's title is required (`SiteSetting#title_present_in_
  # default_locale`); another language's may be left blank. A `TRANSLATED`
  # key in `attributes` is an `ArgumentError`: assigned there it would land
  # in whatever `Mobility.locale` happens to be ambient -- a wrong-language
  # write nobody asked for, so it's refused rather than ignored.
  #
  # The AI settings (`ai_provider`, `ai_model`, `ai_api_key`, translation
  # helpers spec §6.2) are plain `attributes` too, one value for the whole
  # site; what a blank key or "Remove key" means is the Settings screen's
  # to decide (`Admin::SettingsController#assign_ai_key`) -- here, nil
  # clears the key like any other attribute.
  #
  # Needs `settings.manage`; one that changes the enabled `locales` too
  # needs `languages.manage`, the right that owns them everywhere else
  # (`Locales::Enable`/`Disable`/`Configure`). The default language stays a
  # settings field, as on the Settings screen. Recorded as
  # `settings.updated`, and only when something actually changed.
  class Save < ApplicationService
    TRANSLATED = %i[title tagline].freeze

    def initialize(site = Current.site, attributes: {}, translations: {}, actor: Current.actor)
      @site = site
      @attributes = attributes.to_h.symbolize_keys
      misplaced = @attributes.keys & TRANSLATED
      raise ArgumentError, "#{misplaced.join(", ")} must be passed per language in translations:" if misplaced.any?

      @translations = translations.to_h
      @actor = actor
    end

    def call
      return denied("settings.manage", @site) unless authorize!("settings.manage", @site)
      if @attributes.key?(:locales) && !authorize!("languages.manage", @site)
        return denied("languages.manage", @site)
      end

      assign
      logo_changing = @site.attachment_changes.key?("logo")

      saved = SiteSetting.transaction do
        @site.save || raise(ActiveRecord::Rollback)

        changes = Audit::Snapshot.field_changes_for(@site)
        changes["logo"] = [ nil, @site.logo.attached? ? @site.logo.filename.to_s : nil ] if logo_changing
        changes["AI key"] = ai_key_change if @site.saved_change_to_ai_api_key?
        record_event("settings.updated", subject: @site, field_changes: changes) if changes.any?
        true
      end
      return failure(@site) unless saved

      success(@site)
    end

    private

    # The AI API key (translation helpers spec §6.2) is scrubbed from the
    # snapshot and the changes row (`Audit::Snapshot::NEVER_STORED`), so
    # the event says only that it changed -- set, replaced or removed --
    # never what it is. The label is deliberately not `ai_api_key` (or
    # anything else matching a `filter_parameters` entry such as `_key`),
    # which the scrub would drop again.
    def ai_key_change
      @site.saved_change_to_ai_api_key.map { |key| key.present? ? "set" : "not set" }
    end

    def assign
      @site.assign_attributes(@attributes)

      @translations.each do |locale, values|
        Mobility.with_locale(locale) { @site.assign_attributes(values.to_h.symbolize_keys.slice(*TRANSLATED)) }
      end
    end
  end
end
