# When a copy's coming into force was acted on (Task 4b of the drafts plan).
# A copy taken with a time comes into force by the clock, with no write, and
# until now nothing recorded that the addresses had followed it: a window was
# swept, `live_at > created_at` stood in for "may be unswept", older copies
# were read back one by one and a cache key stood in for "already reported".
# With the mark, `PublicSite::Paths.refresh` takes the copies that are due
# (`live_at` passed, not settled), marks them and re-derives their records,
# once, however late.
#
# The partial index is what "the copies that are due" reads: normally empty.
#
# Every copy in force when this runs is marked as it stands, in SQL and with
# no application class: a copy in force at once had its addresses derived by
# the write that took it, and a scheduled one was the old sweep's.
class AddSettledAtToPublishedVersions < ActiveRecord::Migration[8.1]
  def up
    add_column :published_versions, :settled_at, :datetime
    add_index :published_versions, :live_at, where: "settled_at IS NULL", name: "index_published_versions_on_live_at_unsettled"
    execute("UPDATE published_versions SET settled_at = live_at WHERE live_at <= NOW()")
  end

  def down
    remove_column :published_versions, :settled_at
  end
end
