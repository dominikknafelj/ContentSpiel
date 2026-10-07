# The stored half of the public site's content version (technical cleanup
# spec §4.8): one row, one counter. `PublicSite.bump_version!` is the only
# caller of `bump!`, and `PublicSite.content_version` the only reader a
# request needs; see `app/models/public_site.rb` for what moves it and why.
#
# The row is the one with `ROW_ID`. A database built from `db/schema.rb`
# rather than by the migration (every test database, `db:schema:load`) has
# no row: that reads as 0, and the first bump creates it.
module PublicSite
  class Version < ApplicationRecord
    self.table_name = "public_site_versions"

    ROW_ID = 1

    # One query.
    def self.current
      where(id: ROW_ID).pick(:counter) || 0
    end

    # One statement, with no "is there a row" branch in Ruby: `INSERT ...
    # ON CONFLICT (id) DO UPDATE SET counter = counter + 1`. The database
    # counts, so two writers committing at once both count -- each waits for
    # the other's row lock for the length of this statement -- and that
    # holds for the very first bumps too: of two inserts racing for the
    # missing row, the loser's becomes the update.
    def self.bump!
      upsert({ id: ROW_ID, counter: 1 }, unique_by: :id,
        # sql: `upsert`'s ON CONFLICT ... DO UPDATE SET takes SQL text; Arel has no node for the `excluded` row
        on_duplicate: Arel.sql("counter = public_site_versions.counter + 1, updated_at = excluded.updated_at"))
    end
  end
end
