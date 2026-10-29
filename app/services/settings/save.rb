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
  # The mail settings (docs/reference/mail.md) are plain `attributes` too:
  # `mail_server`, `mail_port`, `mail_security`, `mail_sender_name` and
  # `mail_sender_address` (checked by `SiteSetting`'s validations), and the
  # LOGIN, `mail_username` and `mail_password`, which are pulled out and
  # written like the AI key (`#write_mail_login`): straight to their columns,
  # never decrypting what is stored, audited as "Mail login: set / not set".
  # A mail field the host's environment sets (`MailSettings#from_host?`) is
  # not the screen's to change: naming one refuses the whole call, before
  # anything is written.
  #
  # WITHOUT ENCRYPTION KEYS (spec "Security rules") writing the AI key or the
  # mail login raises `ActiveRecord::Encryption::Errors::Configuration` at
  # the first encryption, inside the transaction: it is answered with one
  # sentence (`.no_encryption_keys`), the transaction is rolled back, so
  # nothing of the call is written, and nothing is recorded.
  #
  # Recorded as `settings.updated`, and only when something actually changed.
  class Save < ApplicationService
    TRANSLATED = %i[title tagline].freeze

    MAIL_LOGIN = %i[mail_username mail_password].freeze

    # The attribute of each `MailSettings` field.
    MAIL_ATTRIBUTES = {
      mail_server: :server, mail_port: :port, mail_security: :security, mail_sender_name: :sender_name,
      mail_sender_address: :sender_address, mail_username: :username, mail_password: :password
    }.freeze

    # Looked up at each call, so a later locale switch applies; `raise: true`
    # so a missing key never becomes a "translation missing" sentence.
    def self.no_encryption_keys = I18n.t("admin.settings.save.no_encryption_keys", raise: true)

    def self.set_by_host(attribute)
      I18n.t("admin.settings.save.set_by_host", field: SiteSetting.human_attribute_name(attribute), raise: true)
    end

    def initialize(site = Current.site, attributes: {}, translations: {}, languages: nil, actor: Current.actor)
      @site = site
      @attributes = attributes.to_h.symbolize_keys
      misplaced = @attributes.keys & TRANSLATED
      raise ArgumentError, "#{misplaced.join(", ")} must be passed per language in translations:" if misplaced.any?

      # Kept out of `assign_attributes` -- see `#write_ai_key`.
      @ai_key_given = @attributes.key?(:ai_api_key)
      @new_ai_key = @attributes.delete(:ai_api_key).to_s.strip.presence

      # Kept out of `assign_attributes` too -- see `#write_mail_login`. Only
      # the keys given are written: a login half set by the host posts the
      # other half alone.
      @mail_login = @attributes.slice(*MAIL_LOGIN).transform_values { |value| value.to_s.strip.presence }
      @attributes = @attributes.except(*MAIL_LOGIN)

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

      if site_part? && (from_host = mail_attributes_from_host).any?
        return failure(@site, from_host.map { |attribute| self.class.set_by_host(attribute) })
      end

      needed_languages = languages_part?
      late_refusal = nil
      language_errors = []
      saved = SiteSetting.transaction do
        # The settings row is the one row this service read-modify-writes, so it
        # is locked FIRST (`lock!` re-reads it and raises on a record with
        # unsaved changes, hence before `assign`): what is assigned, compared
        # (`languages_part?`, `Configure#apply`'s "exactly the enabled
        # languages") and saved is the stored row, never the copy loaded
        # earlier in the request, so a language or settings change made
        # meanwhile is not overwritten. `Locales::Enable`/`Disable`/
        # `MakeDefault`/`Configure` take the same lock first, and nothing takes
        # another lock before it. Held until commit, including the synchronous
        # `rebuild_all` below; accepted while sites are small. (The controller's
        # stale-form check runs before the service and is not atomic with this
        # save: it is what tells an editor "reload"; this lock is what keeps the
        # row consistent.)
        @site.lock!

        # The rights were checked against the copy the caller passed; the
        # stored default may differ from it, which can turn a plain site save
        # into a default-language change that needs `languages.manage`.
        if !needed_languages && languages_part? && !authorize!("languages.manage", @site)
          late_refusal = "languages.manage"
          next false
        end

        if site_part?
          assign
          logo_changing = @site.attachment_changes.key?("logo")
        end

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
          mail_login_change = write_mail_login if @mail_login.any?
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
          # "Mail login", like "AI key": matches no `filter_parameters` entry.
          changes["Mail login"] = mail_login_change if mail_login_change
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
      return denied(late_refusal, @site) if late_refusal
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
    rescue ActiveRecord::Encryption::Errors::Configuration
      # The transaction is already rolled back; the row in memory still
      # holds what was assigned and "saved" (see the languages refusal above
      # for why it is reloaded).
      @site.reload
      failure(@site, [ self.class.no_encryption_keys ])
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
      @site.update_columns(ai_api_key: @new_ai_key, ai_api_key_saved_at: (now if @new_ai_key), updated_at: now) # version: none (the AI key is on no public page)
      [ before, @new_ai_key.present? ].map { |set| set ? "set" : "not set" }
    end

    # The mail login (spec decision 2), written as the AI key is and for the
    # same reasons (see `#write_ai_key`): straight to the columns, after the
    # main save and in its transaction, never decrypting what is stored, so a
    # login the current keys can't read can still be replaced or removed.
    # Only the given columns are written (nil removes one);
    # `mail_login_saved_at` ("Set on 14 Oct 2026") is now while any half of
    # the login is stored afterwards, nil once none is. A change to the
    # login is a change of the delivery settings, which `MailSettings`'s
    # fingerprint sees by itself: nothing is cleared here.
    #
    # Returns the audit row's `"Mail login"` change, "set"/"not set" before
    # and after (never a value: `Audit::Snapshot::NEVER_STORED` keeps both
    # columns out of the snapshot), or nil when there was none and still is.
    def write_mail_login
      before = @site.mail_login_set?
      after = MAIL_LOGIN.any? do |column|
        @mail_login.key?(column) ? @mail_login[column].present? : @site.public_send(:"#{column}_before_type_cast").present?
      end
      return nil if !before && !after

      now = Time.current
      @site.update_columns(**@mail_login, mail_login_saved_at: (now if after), updated_at: now) # version: none (the mail login is on no public page)
      [ before, after ].map { |set| set ? "set" : "not set" }
    end

    # The given mail attributes whose field the host's environment sets.
    def mail_attributes_from_host
      given = MAIL_ATTRIBUTES.keys.select { |attribute| @attributes.key?(attribute) || @mail_login.key?(attribute) }
      return [] if given.empty?

      settings = MailSettings.current(@site)
      given.select { |attribute| settings.from_host?(MAIL_ATTRIBUTES[attribute]) }
    end

    # Whether the call carries site fields (or nothing at all, which has
    # always meant a settings save); false for a call that is only `languages:`.
    def site_part?
      @languages.nil? || @attributes.any? || @ai_key_given || @mail_login.any? || @translations.any?
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
