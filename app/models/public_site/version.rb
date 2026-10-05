# The stored half of the public site's content version (technical cleanup
# spec §4.8): one row, one counter. `PublicSite.bump_version!` is the only
# caller of `increment!`, and `PublicSite.content_version` the only reader a
# request needs; see `app/models/public_site.rb` for what moves it and why.
#
# A database built from `db/schema.rb` rather than by the migration (every
# test database) has no row. That reads as 0, and the first increment
# creates the row.
module PublicSite
  class Version < ApplicationRecord
    self.table_name = "public_site_versions"

    # One query.
    def self.current
      order(:id).pick(:counter) || 0
    end

    # `counter = counter + 1` in the database, never read-then-write in Ruby:
    # two writers committing at once both count, each waiting for the other's
    # row lock for the length of one single-row statement.
    #
    # With no row to update, one is created already counted. Two processes
    # doing that at the same moment could each insert one; `current` and this
    # `UPDATE` then keep using whichever has the lowest id, so the counter
    # still only ever goes up.
    def self.increment!
      now = Time.current
      bumped = where(id: order(:id).limit(1).select(:id)).update_all([ "counter = counter + 1, updated_at = ?", now ]) # version: none (this is the bump)
      create!(counter: 1) if bumped.zero?
    end
  end
end
