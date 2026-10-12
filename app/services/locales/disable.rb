module Locales
  # Turns a language off (spec §4.4): removed from site_settings.locales (and
  # dropped from every other entry's `fallbacks`, so nothing is left pointing
  # at a language that no longer resolves), with its public_paths rows
  # deleted so old URLs in that language 404 instead of continuing to
  # resolve. The stored slugs and translated content are left completely
  # untouched -- that's what lets `Locales::Enable` restore the exact same
  # URLs if the language comes back.
  class Disable < ApplicationService
    def initialize(code, actor: Current.actor)
      @code = code.to_s
      @actor = actor
    end

    def call
      site = Current.site
      # `languages.manage` (access-control design spec §3.1): an admin area,
      # with no per-record scope.
      return denied("languages.manage", site) unless authorize!("languages.manage", site)

      default_refused = false
      already_off = false
      saved = SiteSetting.transaction do
        # Locked and re-read before the list is read, so a language change made
        # since `Current.site` was loaded isn't overwritten; held until commit,
        # including the synchronous `rebuild_all` below (accepted while sites
        # are small).
        site.lock!

        # The default language is always the address every unprefixed public
        # URL resolves in (SiteSetting#default_locale_is_enabled requires it to
        # stay enabled) -- disabling it would leave the site with no language
        # to serve at its own root, so this is a rule check rather than
        # something the model's own validation could catch after the fact.
        if @code == default
          default_refused = true
          next false
        end

        # An unknown or already-disabled code is a no-op success, not an
        # error: the caller asked for a state ("fr is off") that's already
        # true, so there's nothing to roll back and nothing to report.
        unless site.locale_codes.include?(@code)
          already_off = true
          next false
        end

        entries = site.locales.reject { |entry| entry["code"].to_s == @code }
        site.locales = entries.map { |entry| without_fallback(entry) }
        next false unless site.save

        PublicPath.where(locale: @code).delete_all # changes: none (addresses are derived rows, not content)
        # Every address in that language is gone, deleted around the
        # callbacks: the public content version moves (deferred to the
        # commit; the settings row's own `after_commit` bumps as well).
        PublicSite.bump_version!
        # Which languages are targets changed, so every stored translation
        # state (`translation_states`) is recomputed. Synchronous and
        # proportional to the site's size; fine while sites are small, and
        # the natural thing to move into a job later.
        Translations::StateIndex.rebuild_all
        record_event("language.disabled", subject: site, field_changes: Audit::Snapshot.field_changes_for(site), metadata: { "code" => @code })
        true
      end

      return failure(site, "The default language can't be disabled") if default_refused
      return success(site) if already_off
      return failure(site) unless saved

      success(site)
    end

    private

    def default = Locales.default

    # Strips `@code` out of one entry's `fallbacks`, so a language that used
    # to fall back to the one just disabled doesn't keep naming a code
    # `SiteSetting#locales_are_well_formed` would then reject as "falls back
    # to a language that isn't enabled".
    def without_fallback(entry)
      fallbacks = Array(entry["fallbacks"]).map(&:to_s) - [ @code ]
      fallbacks.any? ? entry.merge("fallbacks" => fallbacks) : entry.except("fallbacks")
    end
  end
end
