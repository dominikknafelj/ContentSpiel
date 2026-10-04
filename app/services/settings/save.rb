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
  # to decide (`Admin::AiKeysController`, the key's own Save key / Remove
  # key forms) -- here, nil clears the key like any other attribute.
  #
  # `languages:` (decision D5) is CS Studio's path for the language order and
  # each language's fallback: the complete ordered `[{ "code", "fallbacks" }]`
  # list, applied through `Locales::Configure#apply` INSIDE this service's
  # transaction, so one Save is all-or-nothing and records `settings.updated`
  # and/or `language.configured` (each only when something changed). It needs
  # `languages.manage`; the site fields (`attributes`, `translations`) need
  # `settings.manage`. A call that carries both parts needs both rights, and
  # a missing one refuses the WHOLE call: nothing is written and exactly one
  # `access.denied` is recorded. `settings.manage` is checked first, so an
  # actor lacking both is denied for that one. A call with only `languages:`
  # needs only `languages.manage`.
  #
  # The setup wizard still passes `default_locale` and `locales` in
  # `attributes` (needs `settings.manage` plus, for `locales`,
  # `languages.manage`); CS Studio's settings form never permits them -- the
  # default language is `Locales::MakeDefault`, the language list
  # `Enable`/`Disable`/`languages:`.
  #
  # Recorded as `settings.updated`, and only when something actually changed.
  class Save < ApplicationService
    TRANSLATED = %i[title tagline].freeze

    def initialize(site = Current.site, attributes: {}, translations: {}, languages: nil, actor: Current.actor)
      @site = site
      @attributes = attributes.to_h.symbolize_keys
      misplaced = @attributes.keys & TRANSLATED
      raise ArgumentError, "#{misplaced.join(", ")} must be passed per language in translations:" if misplaced.any?

      # Kept out of `assign_attributes` -- see `#write_ai_key`.
      @ai_key_given = @attributes.key?(:ai_api_key)
      @new_ai_key = @attributes.delete(:ai_api_key).to_s.strip.presence

      # Only the translated keys count, and a language left with none is
      # dropped: `{ "en" => {} }` is no site part, so a languages-only call
      # carrying it still needs only `languages.manage`.
      @translations = translations.to_h.transform_values { |values| values.to_h.symbolize_keys.slice(*TRANSLATED) }
        .reject { |_locale, values| values.empty? }
      @languages = languages
      @actor = actor
    end

    def call
      # Every right is checked BEFORE anything is assigned or written, so a
      # refusal leaves nothing behind and records the single `access.denied`.
      if site_part? && !authorize!("settings.manage", @site)
        return denied("settings.manage", @site)
      end
      if languages_part? && !authorize!("languages.manage", @site)
        return denied("languages.manage", @site)
      end

      if site_part?
        assign
        logo_changing = @site.attachment_changes.key?("logo")
      end

      language_errors = []
      saved = SiteSetting.transaction do
        # A languages-only call never ASSIGNS a site field: saving the row
        # here first would normalise columns and record a `settings.updated`
        # for an actor who may not hold `settings.manage`. The row is still
        # saved once, by `Locales::Configure#apply` below (for its `locales`),
        # and that save validates the whole row: a stored value that is
        # validated only when it changes (the time zone, the AI provider, the
        # social links) can't block a reorder, one that is always validated
        # (a negative retention period written around the model) still does,
        # with its own message.
        if site_part?
          @site.save || raise(ActiveRecord::Rollback)
          ai_key_change = write_ai_key if @ai_key_given
          # A new default language (or a changed language list through the
          # wizard's `attributes`) changes what every record's state is
          # relative to; anything else only the site's own title and tagline
          # (`translation_states`). The `languages:` path can't change the set
          # of codes (`Locales::Configure` refuses that), so a reorder or a
          # fallback change never rebuilds the whole index.
          locales_changed = @site.saved_change_to_default_locale? || @site.saved_change_to_locales?

          # The settings event is built from THIS save's changes, before the
          # languages write below saves the row a second time (which replaces
          # `saved_changes`).
          changes = Audit::Snapshot.field_changes_for(@site)
          changes["logo"] = [ nil, @site.logo.attached? ? @site.logo.filename.to_s : nil ] if logo_changing
          changes["AI key"] = ai_key_change if ai_key_change
          record_event("settings.updated", subject: @site, field_changes: changes) if changes.any?
        end

        if @languages
          language_errors = Locales::Configure.new(@languages, actor: @actor).apply(@site)
          raise ActiveRecord::Rollback if language_errors.any?
        end

        if site_part?
          locales_changed ? Translations::StateIndex.rebuild_all : Translations::StateIndex.refresh(@site)
        end
        true
      end
      if language_errors.any?
        # The site part (if any) was saved and then rolled back with the
        # refused language part, and `Configure#apply` left its entries
        # assigned -- yet `@site` is `Current.site`, the one object everything
        # rendered after this reads (the 422 re-render, the layout), and it
        # would go on reporting the rolled-back values as stored: not dirty,
        # so not even a later save would notice. Reload it, as
        # `Locales::MakeDefault` does (`restore_attributes` doesn't reach
        # Mobility's jsonb values, and a reload also drops a pending logo
        # attachment). The errors survive a reload; what was typed comes back
        # to the form from the request (`Admin::SettingsScreen::Values`).
        # A plain validation failure of the site part is NOT reloaded: nothing
        # was written, so the record is honestly dirty, and its own `errors`
        # belong to the values still assigned.
        @site.reload
        return failure(@site, language_errors)
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
    #
    # `ai_api_key_saved_at` (decision D11) is written in the same statement
    # and cleared with the key: it is when the key was saved, not an audited
    # setting (`Audit::Snapshot::IGNORED_CHANGES`; the event already says "AI
    # key: set / not set"). An unrelated save never touches it.
    def write_ai_key
      before = @site.ai_api_key_set?
      return nil if !before && @new_ai_key.nil?

      now = Time.current
      @site.update_columns(ai_api_key: @new_ai_key, ai_api_key_saved_at: (now if @new_ai_key), updated_at: now)
      [ before, @new_ai_key.present? ].map { |set| set ? "set" : "not set" }
    end

    # Whether the call carries site fields (or nothing at all, which has
    # always meant a settings save); false for a call that is only `languages:`.
    def site_part?
      @languages.nil? || @attributes.any? || @ai_key_given || @translations.any?
    end

    # Whether the call needs `languages.manage`: the order (`languages:`), the
    # wizard's `locales`, or a CHANGED default language. The default is a
    # `Locales::MakeDefault` matter in CS Studio (it needs `languages.manage`),
    # so a `settings.manage`-only actor can't reach the same write through
    # here, even if a controller ever permitted the field.
    def languages_part?
      @languages || @attributes.key?(:locales) ||
        (@attributes.key?(:default_locale) && @attributes[:default_locale].to_s != @site.default_locale.to_s)
    end

    def assign
      @site.assign_attributes(@attributes)

      @translations.each do |locale, values|
        Mobility.with_locale(locale) { @site.assign_attributes(values.to_h.symbolize_keys.slice(*TRANSLATED)) }
      end
    end
  end
end
