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

      # Asking for what is already true is a no-op success, like `Enable`.
      return success(site) if site.default_locale.to_s == @code
      return failure(site, "#{@code} isn't an enabled language") unless site.locale_codes.include?(@code)

      site.default_locale = @code
      saved = SiteSetting.transaction do
        site.save || raise(ActiveRecord::Rollback)

        Translations::StateIndex.rebuild_all
        record_event("language.default_changed", subject: site,
          field_changes: Audit::Snapshot.field_changes_for(site), metadata: { "code" => @code })
        true
      end
      return failure(site) unless saved

      success(site)
    end
  end
end
