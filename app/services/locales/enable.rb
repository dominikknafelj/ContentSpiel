module Locales
  # Turns a supported language on (spec §4.4): it joins site_settings.locales,
  # every page and post gets a slug in it (from the fallback chain -- existing
  # slugs are never touched, so re-enabling a language restores its old
  # URLs), and public_paths is synced so the new URLs exist immediately.
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
      # `languages.manage` (access-control design spec §3.1): an admin area,
      # with no per-record scope.
      return denied("languages.manage", site) unless authorize!("languages.manage", site)
      already_enabled = false
      SiteSetting.transaction do
        # The one settings row is locked (and so re-read) before the language
        # list is read: `Current.site` is a copy loaded earlier in the request,
        # and a language change made since then (another editor, another
        # request) would otherwise be overwritten by this copy's list. The
        # lock is held until commit, including the synchronous
        # `StateIndex.rebuild_all` below; accepted while sites are small.
        site.lock!
        if site.locale_codes.include?(@code)
          already_enabled = true
          next
        end

        entry = { "code" => @code }
        entry["fallbacks"] = @fallbacks if @fallbacks.any?
        site.locales = site.locales + [ entry ]
        raise ActiveRecord::Rollback unless site.save

        changes = Audit::Snapshot.field_changes_for(site)

        [ Page, Post ].each do |model|
          model.find_each do |record|
            record.fill_blank_slugs([ @code ])
            record.update_columns(slug: record.read_attribute(:slug)) if record.changed?
          end
        end

        # A full sync, not `rebuild!`: `rebuild!` truncates `public_paths`
        # first (spec §5.4), which threw away every redirect row -- the old
        # URLs of renamed or moved pages and posts, in *every* language --
        # the moment any language was enabled (spec §9.2 promises old URLs
        # keep 301ing). Syncing the tree top-down and then every post only
        # adds the new language's rows (and corrects any other stale ones
        # the same way a save would), leaving existing redirects in place.
        # Pages before posts, since a post's path is read off its canonical
        # page's freshly written row.
        root = Page.find_by(parent_id: nil)
        PublicSite::Paths.sync_subtree(root) if root
        PublicSite::Paths.sync_posts(nil)
        # Which languages are targets changed, so every stored translation
        # state (`translation_states`) is recomputed. Synchronous and
        # proportional to the site's size; fine while sites are small, and
        # the natural thing to move into a job later.
        Translations::StateIndex.rebuild_all

        record_event("language.enabled", subject: site, field_changes: changes, metadata: { "code" => @code })
      end

      return success(site) if already_enabled
      return failure(site) if site.errors.any?

      success(site)
    end
  end
end
