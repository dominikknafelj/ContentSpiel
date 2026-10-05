# The public site's content version (technical cleanup spec §4.8): one row
# holding a counter that `PublicSite.bump_version!` increments whenever
# published output can have changed. A table of its own rather than a column
# on `site_settings`, because that row's `updated_at` is the Settings form's
# stale-check base and must not move with every published edit.
#
# The row is inserted here so a migrated database starts with one; a database
# built from `db/schema.rb` (a test database, `db:schema:load`) has none, and
# `PublicSite::Version` reads that as 0 and creates the row at the first bump.
class CreatePublicSiteVersions < ActiveRecord::Migration[8.1]
  def up
    create_table :public_site_versions do |t|
      t.bigint :counter, null: false, default: 0
      t.timestamps
    end

    execute "INSERT INTO public_site_versions (counter, created_at, updated_at) VALUES (0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
  end

  def down
    drop_table :public_site_versions
  end
end
