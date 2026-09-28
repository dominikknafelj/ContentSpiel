module Locales
  # Edits fallbacks and reorders the site's *already-enabled* languages
  # (spec §6.1) -- unlike `Enable`/`Disable`, which change which codes are
  # on at all, this only ever rewrites the order and each entry's
  # `fallbacks` for the exact same set of codes already enabled.
  # `Locales.fallback_chain`'s own final tier ("every other enabled
  # language, in order") is what actually makes the *order* meaningful: it's
  # the tie-breaker once a locale's own explicit fallbacks (checked first)
  # have already come up empty, so reordering here changes which language a
  # blank translation falls back to even when no `fallbacks` entry names it
  # directly.
  #
  # `entries` is the *complete*, ordered replacement for `site.locales` --
  # an ordered Array of `{ "code", "fallbacks" }` (fallbacks optional) --
  # not a partial patch; the caller (the languages screen's own form) always
  # submits every enabled language's row together, the same way a content
  # block's own `ContentBlocks::Reorder` is handed the complete new order
  # rather than a delta.
  class Configure < ApplicationService
    def initialize(entries, actor: Current.actor)
      @entries = Array(entries).map { |entry| normalize(entry) }
      @actor = actor
    end

    def call
      site = Current.site
      # `languages.manage` (access-control design spec §3.1): an admin area,
      # with no per-record scope.
      return denied("languages.manage", site) unless authorize!("languages.manage", site)

      # A code this call doesn't already recognize as enabled -- an
      # attempt to sneak `Enable`/`Disable` in through this endpoint
      # instead, or a stale form submitted after another tab already
      # changed which languages are on -- is refused outright, before
      # `site.locales` is ever touched: `SiteSetting#locales_are_well_
      # formed` alone wouldn't catch a *reordered-into-same-set* swap like
      # that, since it only validates the codes it's handed are supported
      # and self-consistent, not that they match whatever was enabled a
      # moment ago.
      unless @entries.map { |entry| entry["code"] }.sort == site.locale_codes.sort
        return failure(site, "must list exactly the enabled languages")
      end

      site.locales = @entries
      saved = SiteSetting.transaction do
        site.save || raise(ActiveRecord::Rollback)

        changes = Audit::Snapshot.field_changes_for(site)
        record_event("language.configured", subject: site, field_changes: changes) if changes.any?
        true
      end
      return failure(site) unless saved

      success(site)
    end

    private

    def normalize(entry)
      code = (entry[:code] || entry["code"]).to_s
      fallbacks = Array(entry[:fallbacks] || entry["fallbacks"]).map(&:to_s).reject(&:blank?)
      fallbacks.any? ? { "code" => code, "fallbacks" => fallbacks } : { "code" => code }
    end
  end
end
