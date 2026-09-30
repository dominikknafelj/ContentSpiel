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
      validate :slug_present_in_every_enabled_locale
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

      public_send("#{::Mobility.normalize_locale_accessor(:slug, locale)}=", slugify(title))
    end
  end

  # Whether `value` is some other *kept* record's slug in `locale` within the
  # same `localized_slug_scope`. Trashed records don't hold their slug (trash
  # spec §2 "URLs: freed at once") -- a page rebuilt in the trashed one's
  # place must be able to take its address, and `Trash::Restore` uses this
  # same question to find a free `-2`, `-3` suffix instead.
  #
  # `.i18n` reads the locale off `Mobility.locale` when `where` runs rather
  # than from an argument, so the query is built inside the locale it asks
  # about. The `trashed_at` guard is a column check rather than an
  # `include?(Trashable)` so this concern stays usable by a model that has no
  # trash at all.
  def slug_taken?(locale, value)
    ::Mobility.with_locale(locale) do
      scope = self.class.i18n.where(slug: value).where(localized_slug_scope => public_send(localized_slug_scope))
      scope = scope.where(trashed_at: nil) if self.class.column_names.include?("trashed_at")
      scope = scope.where.not(id: id) if persisted?
      scope.exists?
    end
  end

  private

  # `String#parameterize` transliterates through ASCII (`I18n.transliterate`)
  # and then drops anything left that isn't `[a-z0-9-]` -- fine for a title
  # with Latin letters and diacritics ("Über uns" -> "uber-uns"), but a
  # no-op-to-empty for one that has none at all: transliteration has nothing
  # to map Japanese, Korean, Thai, Hebrew, Arabic, etc. onto, so every
  # character is dropped and the result is "". A CMS offering ~37 languages
  # (spec §4.1) can't require every title to contain a Latin letter just to
  # get a URL, so a blank `parameterize` result falls back to a
  # Unicode-preserving slug instead: downcase, keep letters and digits in any
  # script (`\p{L}`/`\p{N}`), collapse every other run of characters to a
  # single "-", and trim leading/trailing "-".
  #
  # The result can contain raw Unicode ("日本語のタイトル") rather than only
  # ASCII -- that is fine on the wire: a URL's path segment is percent-encoded
  # by whatever sends the request (a browser, a link, `curl`), and Rails'
  # router decodes it straight back before `PublicSite::Paths`/`PublicPath`
  # ever compares it, the same way it already decodes any other non-ASCII or
  # reserved character in a path segment.
  def slugify(title)
    slug = title.parameterize
    return slug if slug.present?

    title.downcase.gsub(/[^\p{L}\p{N}]+/, "-").gsub(/\A-+|-+\z/, "")
  end

  # A non-root page/post with no slug in some enabled locale would have no
  # URL there at all (`PublicSite::Paths.page_path`/`post_path` return nil
  # for a blank segment rather than erroring) -- silent and easy to miss, so
  # this catches it as a form error instead.
  #
  # Checked per *enabled* locale, not "present in any locale" the way
  # `title_present_in_any_locale` (Page/Post) is: a title in any locale is
  # enough because untranslated locales fall back when reading it back, but
  # a slug that's missing in one enabled locale has no fallback --
  # `fill_blank_slugs` above is what's supposed to prevent that gap, filling
  # every enabled locale from a title (its own, or the first one found
  # walking its fallback chain). This validation exists for the one way that
  # fill can still come up empty: `slugify` returns "" for a title with no
  # letters or digits at all (bare punctuation/whitespace) in every locale it
  # tried, same as a title that's blank outright.
  #
  # Raw jsonb hash, not the per-locale accessor: a locale that has never been
  # written at all is absent from the hash entirely (as opposed to present
  # with a blank value), and `Hash#[]` on a missing key is nil either way --
  # reading it directly here, once, is simpler than a `public_send` per
  # locale for the same result.
  def slug_present_in_every_enabled_locale
    return unless generates_slugs?

    slugs = read_attribute(:slug).to_h

    ::Locales.enabled.each do |locale|
      next if slugs[locale.to_s].present?

      # Reported against `slug_de`, and named per locale, for the same
      # reason `slug_is_unused_in_every_locale` below reports its own
      # collisions that way: whichever locale is missing a slug is not
      # necessarily the one the editor is looking at.
      errors.add(::Mobility.normalize_locale_accessor(:slug, locale), :blank,
        message: "can't be blank in #{locale.to_s.upcase}")
    end
  end

  # `validates :slug, uniqueness:` would emit `WHERE pages.slug = 'about'`,
  # comparing a jsonb column to a string -- which Postgres rejects outright.
  # Mobility's `.i18n` scope rewrites the condition into a lookup of one
  # locale's key inside the column, so two records may share a slug as long
  # as they don't share it *in the same locale* and the same
  # `localized_slug_scope`.
  #
  # Every enabled locale is checked, not just `Mobility.locale`: the admin
  # form writes all of them in a single request that runs under one ambient
  # locale, so checking only that one would let a collision in any other
  # locale through unreported.
  #
  # A trashed record skips the check entirely: it never needs a unique slug
  # while it's in the trash (it has no URL at all -- `PublicSite::Paths.
  # compute_path`), and a kept record may have taken its slug since, which
  # must not make the trashed one unsaveable. `Trash::Restore` finds it a
  # free `-2`, `-3` suffix on the way back out instead.
  def slug_is_unused_in_every_locale
    return if respond_to?(:trashed?) && trashed?

    ::Locales.enabled.each do |locale|
      accessor = ::Mobility.normalize_locale_accessor(:slug, locale)

      # The literal value for this locale. The plain `slug` reader no longer
      # falls back to another locale (this task), but reading it out
      # explicitly by accessor rather than through the ambient locale keeps
      # this correct regardless -- it asks whether *this* locale's slug is
      # taken, not whichever locale happens to be ambient.
      value = public_send(accessor)
      next if value.blank?

      taken = slug_taken?(locale, value)

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
