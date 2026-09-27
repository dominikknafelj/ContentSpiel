module Locales
  # Turns a supported language on (spec §4.4): it joins site_settings.locales,
  # every page and post gets a slug in it (from the fallback chain -- existing
  # slugs are never touched, so re-enabling a language restores its old
  # URLs), and public_paths is rebuilt so the new URLs exist immediately.
  #
  # An unknown/unsupported code isn't checked explicitly here -- `site.save`
  # below fails on it the same way any other malformed `locales` entry would
  # (`SiteSetting#locales_are_well_formed`), so there's exactly one place
  # that decides what counts as a valid locale.
  class Enable < ApplicationService
    def initialize(code, fallbacks: [], actor: Current.actor)
      @code, @fallbacks, @actor = code.to_s, Array(fallbacks).map(&:to_s), actor
    end

    def call
      site = Current.site
      authorize!(:enable_locale, site)
      return success(site) if site.locale_codes.include?(@code)

      entry = { "code" => @code }
      entry["fallbacks"] = @fallbacks if @fallbacks.any?
      site.locales = site.locales + [ entry ]

      SiteSetting.transaction do
        raise ActiveRecord::Rollback unless site.save

        [ Page, Post ].each do |model|
          model.find_each do |record|
            record.fill_blank_slugs([ @code ])
            record.update_columns(slug: record.read_attribute(:slug)) if record.changed?
          end
        end

        # `rebuild!` truncates `public_paths` before recomputing it (spec
        # §5.4), so any redirect rows (old URLs from a previous slug/move)
        # are lost the moment a language is enabled -- accepted for now,
        # greenfield, no production traffic depends on those redirects
        # surviving yet. If that turns out to matter, the fix is a
        # `sync_all` that walks every record with `sync`/`sync_posts`
        # instead of truncating first, keeping existing redirect rows intact.
        PublicSite::Paths.rebuild!
      end

      return failure(site) if site.errors.any?

      record_event(:locale_enabled, code: @code)
      success(site)
    end
  end
end
