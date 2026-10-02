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

      # Kept out of `assign_attributes` -- see `#write_ai_key`.
      @ai_key_given = @attributes.key?(:ai_api_key)
      @new_ai_key = @attributes.delete(:ai_api_key).to_s.strip.presence

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
        ai_key_change = write_ai_key if @ai_key_given

        changes = Audit::Snapshot.field_changes_for(@site)
        changes["logo"] = [ nil, @site.logo.attached? ? @site.logo.filename.to_s : nil ] if logo_changing
        changes["AI key"] = ai_key_change if ai_key_change
        record_event("settings.updated", subject: @site, field_changes: changes) if changes.any?
        true
      end
      return failure(@site) unless saved

      success(@site)
    end

    private

    # The AI API key (translation helpers spec §6.2), written straight to
    # its column after the main save (inside the same transaction, so a
    # refused save writes no key either) rather than through
    # `assign_attributes`: assigning an encrypted attribute makes dirty
    # tracking decrypt the *old* value to compare, and a stored key the
    # current encryption keys can't read (lost, rotated) would then make it
    # impossible to remove or replace -- the very fix for it.
    #
    # Returns the audit row's `"AI key"` change, `[before, after]` as
    # "set"/"not set" (never the key; `Audit::Snapshot::NEVER_STORED`
    # scrubs the column itself, and the label deliberately doesn't match
    # the `_key` filter, which would drop it again), or nil when nothing
    # changed (removing a key that isn't there). A new key always counts as
    # a change: telling it apart from the stored one would mean decrypting.
    def write_ai_key
      before = @site.ai_api_key_set?
      return nil if !before && @new_ai_key.nil?

      @site.update_columns(ai_api_key: @new_ai_key, updated_at: Time.current)
      [ before, @new_ai_key.present? ].map { |set| set ? "set" : "not set" }
    end

    def assign
      @site.assign_attributes(@attributes)

      @translations.each do |locale, values|
        Mobility.with_locale(locale) { @site.assign_attributes(values.to_h.symbolize_keys.slice(*TRANSLATED)) }
      end
    end
  end
end
