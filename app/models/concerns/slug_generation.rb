# Fills each locale's blank slug from a title (spec §10.1), so an editor never
# has to type a URL segment. The title source for a given locale, in order:
#
#   1. that locale's own title, if present;
#   2. otherwise the site's default-locale title (`SiteSetting#default_locale`
#      -- a runtime setting, not this app's fixed English default), if
#      present;
#   3. otherwise the first present title, walking `Mobility.available_locales`
#      in order.
#
# (2) exists because a site set up in, say, German titles its early pages only
# in German, leaving every other locale's title -- and, before this, slug --
# blank. A blank slug on a non-root page is not a harmless gap: `build_path`
# drops it and the page's path collapses onto its parent's (see `page.rb`'s
# own comment above `validates :slug` for the two-pages-one-URL collision that
# produces -- for a child of Home, the parent's path is "/", the homepage's
# own). (3) is the last resort for when even the default locale has no title
# of its own: the fallback still has to be *some* present title rather than
# none, or the same collapse happens anyway.
#
# Reads the raw jsonb title hash rather than the Mobility reader, which would
# fall back to a fixed :en regardless of the site's actual default locale.
# Never overwrites a slug that is already set -- changing a published page's
# URL must stay a deliberate act, whether that slug came from this locale's
# own title or a fallback one.
module SlugGeneration
  extend ActiveSupport::Concern

  included do
    before_validation :fill_blank_slugs_from_titles
  end

  private

  def fill_blank_slugs_from_titles
    return unless generates_slugs?

    blank_locales = ::Mobility.available_locales.reject do |locale|
      public_send(::Mobility.normalize_locale_accessor(:slug, locale)).present?
    end
    return if blank_locales.empty?

    titles = read_attribute(:title).to_h

    # Only computed when there's at least one blank slug to fill: it reads
    # `Current.site`, a database row on first access, and most saves (an edit
    # to an already-fully-slugged record) have nothing for it to do.
    fallback_title = blank_slug_fallback_title(titles)

    blank_locales.each do |locale|
      title = titles[locale.to_s].presence || fallback_title
      next if title.blank?

      public_send("#{::Mobility.normalize_locale_accessor(:slug, locale)}=", title.parameterize)
    end
  end

  # Orders (2) and (3) above. Computed once per save rather than once per
  # locale -- neither step depends on which locale is currently being filled,
  # only on the titles hash and the site's default locale.
  def blank_slug_fallback_title(titles)
    default_locale = ::Current.site.default_locale
    titles[default_locale].presence ||
      ::Mobility.available_locales.map { |locale| titles[locale.to_s] }.compact_blank.first
  end

  def generates_slugs?
    true
  end
end
