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
      authorize!(:disable_locale, site)

      # The default language is always the address every unprefixed public
      # URL resolves in (SiteSetting#default_locale_is_enabled requires it to
      # stay enabled) -- disabling it would leave the site with no language
      # to serve at its own root, so this is a rule check rather than
      # something the model's own validation could catch after the fact.
      return failure(site, "The default language can't be disabled") if @code == default

      # An unknown or already-disabled code is a no-op success, not an
      # error: the caller asked for a state ("fr is off") that's already
      # true, so there's nothing to roll back and nothing to report.
      return success(site) unless site.locale_codes.include?(@code)

      entries = site.locales.reject { |entry| entry["code"].to_s == @code }
      site.locales = entries.map { |entry| without_fallback(entry) }

      saved = SiteSetting.transaction do
        next false unless site.save

        PublicPath.where(locale: @code).delete_all
        true
      end

      return failure(site) unless saved

      record_event(:locale_disabled, code: @code)
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
