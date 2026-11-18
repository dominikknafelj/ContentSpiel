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

    # A restored backup rewinds the counter, so the values that follow were
    # already used and a render or an ETag made under one of them would be
    # served for the restored content. Every bump adds 1 and a jump sets the
    # counter to `floor`, the wall clock in microseconds, so after a jump
    # the counter is above every value it held before, as long as it never
    # moved faster than one bump a microsecond. `GREATEST(counter + 1,
    # floor)` keeps a jump from ever moving the counter back. One statement,
    # like `bump!`: a new row's counter is `floor`, an existing row's the
    # greater of the two, read from `excluded`, so nothing is interpolated.
    # A row of another id is no counter anyone reads: it goes, so the table
    # holds the one row. Returns the new counter.
    def self.jump_past!(floor)
      transaction do
        where.not(id: ROW_ID).delete_all # version: none (the counter's own table; this write is the jump)
        upsert({ id: ROW_ID, counter: floor }, unique_by: :id, returning: :counter,
          # sql: `upsert`'s ON CONFLICT ... DO UPDATE SET takes SQL text; Arel has no node for the `excluded` row or GREATEST
          on_duplicate: Arel.sql("counter = GREATEST(public_site_versions.counter + 1, excluded.counter), updated_at = excluded.updated_at")).rows.first.first
      end
    end
  end
end
