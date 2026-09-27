# Keeps a record's rows in public_paths in step with its slugs (spec §5.4),
# and refuses a slug whose resulting path another record already holds --
# as a form error, before the unique index would reject it as an exception.
module HasPublicPaths
  extend ActiveSupport::Concern

  included do
    has_many :public_paths, as: :record, dependent: :delete_all
    validate :public_paths_are_available
  end

  def full_path(locale)
    PublicSite::Paths.current_path(self, locale)
  end

  private

  # A path already held by *another* record's current row is a validation
  # error (spec §5.2), reported against the slug that produces it -- the same
  # way `LocalizedSlug`'s own sibling-slug check attributes a collision to the
  # locale it clashes in, so the admin form marks the tab that actually needs
  # editing rather than a generic `:base` error nobody can act on.
  #
  # This is the guard against the two-pages-one-URL collision `Page`'s old
  # `cached_paths`/`build_path` allowed by accident (a blank non-root slug
  # collapsing onto its parent's path): `PublicSite::Paths.compute` already
  # returns nil rather than a borrowed path for that case, and `taken` below
  # additionally catches two *different*, non-blank slugs that would still
  # resolve to the same address.
  def public_paths_are_available
    PublicSite::Paths.compute(self).each do |locale, path|
      next if path.nil?

      taken = PublicPath.current.where(locale: locale, path: path).where.not(record_type: self.class.name, record_id: id).exists?
      next unless taken

      errors.add(Mobility.normalize_locale_accessor(:slug, locale), :taken,
        message: "gives the address #{path}, which is already taken in #{locale.upcase}")
    end
  end
end
