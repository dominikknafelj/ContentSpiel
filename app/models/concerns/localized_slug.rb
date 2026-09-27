# Fills each locale's blank slug from a title (spec §10.1), so an editor never
# has to type a URL segment. The title source for a given locale, in order:
#
#   1. that locale's own title, if present;
#   2. otherwise the first present title walking that locale's fallback
#      chain (`Locales.fallback_chain`) -- the site's runtime default
#      locale first, then its remaining enabled locales in order.
#
# (2) exists because a site set up in, say, German titles its early pages only
# in German, leaving every other locale's title -- and, before this, slug --
# blank. A blank slug on a non-root page is not a harmless gap:
# `PublicSite::Paths.page_path` returns nil for it rather than a path, so the
# page would have no URL at all in that locale (see `page.rb`'s own comment
# above `validates :slug`, which is what actually keeps a blank segment from
# ever reaching `PublicSite::Paths` in the first place -- this fill is what
# keeps an untranslated locale from ever needing that validation to fire).
#
# Reads the raw jsonb title hash rather than the Mobility reader, which would
# fall back to a fixed :en regardless of the site's actual default locale (and
# which, since this task, no longer falls back on its own at all -- see
# config/initializers/mobility.rb). Never overwrites a slug that is already
# set -- changing a published page's URL must stay a deliberate act, whether
# that slug came from this locale's own title or a fallback one.
#
# Also absorbs the per-locale slug uniqueness validation `Page` and `Post`
# used to duplicate between them (spec §3): `localized_slug scope:` names the
# column two records must share for their slugs to actually clash.
module LocalizedSlug
  extend ActiveSupport::Concern

  class_methods do
    # `scope:` names the column two records must share for their slugs to
    # clash: siblings (`parent_id`) for pages, the content type for posts.
    def localized_slug(scope:)
      class_attribute :localized_slug_scope, instance_writer: false, default: scope
      before_validation :fill_blank_slugs
      validate :slug_is_unused_in_every_locale
    end
  end

  # Public so `Locales::Enable` can fill a newly enabled language's slugs.
  def fill_blank_slugs(locales = Locales.enabled)
    return unless generates_slugs?

    blank_locales = locales.reject do |locale|
      public_send(::Mobility.normalize_locale_accessor(:slug, locale)).present?
    end
    return if blank_locales.empty?

    titles = read_attribute(:title).to_h

    blank_locales.each do |locale|
      # This locale's own title first, then the first present title walking
      # its fallback chain -- computed per locale (unlike the old
      # `SiteSetting#default_locale`-then-first rule, which was the same for
      # every blank locale) because two blank locales can have different
      # fallback chains, e.g. one configured with its own extra fallback.
      title = titles[locale.to_s].presence ||
        ::Locales.fallback_chain(locale).map { |code| titles[code.to_s] }.compact_blank.first
      next if title.blank?

      public_send("#{::Mobility.normalize_locale_accessor(:slug, locale)}=", title.parameterize)
    end
  end

  private

  # `validates :slug, uniqueness:` would emit `WHERE pages.slug = 'about'`,
  # comparing a jsonb column to a string -- which Postgres rejects outright.
  # Mobility's `.i18n` scope rewrites the condition into a lookup of one
  # locale's key inside the column, so two records may share a slug as long
  # as they don't share it *in the same locale* and the same
  # `localized_slug_scope`.
  #
  # Every enabled locale is checked, not just `Mobility.locale`: the admin
  # form writes all of them in a single request that runs under one ambient
  # locale, so checking only that one lets the rest through to the per-locale
  # unique indexes, where the collision surfaces as a raw Postgres error
  # instead of a form error.
  def slug_is_unused_in_every_locale
    ::Locales.enabled.each do |locale|
      accessor = ::Mobility.normalize_locale_accessor(:slug, locale)

      # The literal value for this locale. The plain `slug` reader no longer
      # falls back to another locale (this task), but reading it out
      # explicitly by accessor rather than through the ambient locale keeps
      # this correct regardless -- it asks whether *this* locale's slug is
      # taken, not whichever locale happens to be ambient.
      value = public_send(accessor)
      next if value.blank?

      # `.i18n` reads the locale off `Mobility.locale` when `where` runs
      # rather than from an argument, so the query is built inside the locale
      # it asks about.
      taken = ::Mobility.with_locale(locale) do
        scope = self.class.i18n.where(slug: value).where(localized_slug_scope => public_send(localized_slug_scope))
        scope = scope.where.not(id: id) if persisted?
        scope.exists?
      end

      # Reported against `slug_de` rather than `slug`, so the admin form marks
      # the offending locale's tab instead of an ambient field nobody edits.
      #
      # The message itself names the locale too, not just the field: a slug
      # here can arrive via this concern's own fallback fill rather than
      # anything the editor typed into this tab, so "has already been taken"
      # alone would send them looking at the wrong one.
      errors.add(accessor, :taken, message: "has already been taken in #{locale.to_s.upcase}") if taken
    end
  end

  def generates_slugs?
    true
  end
end
