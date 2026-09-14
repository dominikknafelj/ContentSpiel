# A page's URL path is derived from its ancestors' slugs, and those slugs are
# translated -- so the path differs per locale (`{"en" => "/about/team", "de"
# => "/ueber-uns/team"}`). Deriving it on every request would mean walking the
# hierarchy table for every candidate page; `Page` computes it once per save
# instead and the catch-all route matches against this column.
class AddCachedPathsToPages < ActiveRecord::Migration[8.1]
  # Hardcoded rather than read from I18n, for the same reason CreatePages
  # hardcodes them: a migration is a historical snapshot and must not change
  # meaning when the site adds a locale later.
  LOCALES = %w[en de es].freeze

  def change
    add_column :pages, :cached_paths, :jsonb, null: false, default: {}

    # One expression index per locale, matching the shape of the lookup
    # (`cached_paths ->> 'en' = '/about/team'`) that `Page.find_by_full_path`
    # runs on every request. Not unique: a page with no slug at all resolves to
    # its parent's path, which is a content mistake to surface in the admin,
    # not a constraint violation to raise mid-request.
    LOCALES.each do |locale|
      add_index :pages, "(cached_paths ->> '#{locale}')",
        name: "index_pages_on_cached_path_#{locale}"
    end
  end
end
