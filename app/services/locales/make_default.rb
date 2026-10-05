module Locales
  # Makes an already-enabled language the site's default (decision D8): the
  # one every unprefixed public URL is served in and the original every other
  # language is a translation of. An instant action behind a dialog on the
  # Settings screen, not a field of the settings form.
  #
  # Needs `languages.manage` -- NOT `settings.manage` (decision D9), even
  # though the value lives in `site_settings.default_locale`: which languages
  # exist, in what order and which one leads is one question that
  # `Enable`/`Disable`/`Configure` all answer under the right that owns
  # languages, so a languages-only editor must be able to finish the job and a
  # settings-only editor must not be able to re-point every translation.
  #
  # The title and tagline a new default doesn't have yet are carried over from
  # the old one by the model itself (`SiteSetting#carry_translations_into_new_
  # default_locale`, a `before_validation`), so the site keeps its name; this
  # service only assigns the code. Everything's translation state is relative
  # to the default, so `StateIndex.rebuild_all` runs here, synchronously like
  # `Enable`/`Disable`.
  class MakeDefault < ApplicationService
    def initialize(code, actor: Current.actor)
      @code = code.to_s
      @actor = actor
    end

    def call
      site = Current.site
      return denied("languages.manage", site) unless authorize!("languages.manage", site)

      outcome = nil
      saved = SiteSetting.transaction do
        # Locked and re-read before anything is decided or assigned: the checks
        # below and the new `locales` are computed from the stored row, not from
        # the `Current.site` copy loaded earlier in the request. Held until
        # commit, including the synchronous `rebuild_all` (accepted while sites
        # are small).
        site.lock!

        # Asking for what is already true is a no-op success, like `Enable`.
        if site.default_locale.to_s == @code
          outcome = :unchanged
          next false
        end
        if @code.blank?
          outcome = "Choose an enabled language"
          next false
        end
        unless site.locale_codes.include?(@code)
          outcome = "#{@code} isn't an enabled language"
          next false
        end

        site.default_locale = @code
        # The new default has nothing to fall back to: the default IS the last
        # resort of every chain (`Locales.fallback_chain`), and the card shows its
        # select as a disabled "None (default)", so no screen could clear fallbacks
        # it was stored with while the chain would still apply them. Cleared here,
        # in the same save (and so in the event's field changes). Nobody else's
        # fallbacks change, and the OLD default keeps whatever it had: it is an
        # ordinary language now and its select shows its first entry.
        site.locales = site.locales.map { |entry| entry["code"] == @code ? entry.except("fallbacks") : entry }
        site.save || raise(ActiveRecord::Rollback)

        Translations::StateIndex.rebuild_all
        record_event("language.default_changed", subject: site,
          field_changes: Audit::Snapshot.field_changes_for(site), metadata: { "code" => @code })
        true
      end
      return success(site) if outcome == :unchanged
      return failure(site, outcome) if outcome
      unless saved
        # The model object is `Current.site`, shared for the rest of the
        # request: take the messages, then reload, which drops the default and the carried
        # title/tagline that were only assigned in memory (`restore_attributes`
        # doesn't reach Mobility's jsonb values).
        errors = site.errors.full_messages
        site.reload
        return failure(site, errors)
      end

      success(site)
    end
  end
end
