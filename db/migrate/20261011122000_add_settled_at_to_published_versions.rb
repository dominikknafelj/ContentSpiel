# When a copy's beginning to show was acted on (Task 4b of the drafts plan).
# A copy shows from the later of its own time (`live_at`) and its record's
# (`published_at`), and neither moment writes a row. Until now nothing
# recorded that the addresses had followed: two windows were swept, `live_at
# > created_at` stood in for "may be unswept", older copies were read back
# one by one and a cache key stood in for "already reported". With the mark,
# `PublicSite::Paths.refresh` takes the copies that are due (showing, not
# settled), marks them and re-derives their records, once, however late.
#
# The partial index is what "the copies that are due" reads: the pending
# changes and the scheduled records' copies, and nothing else for long (a
# copy of a record that is not published is marked by the first refresh
# that meets it, `Publishing::Version.settle!`).
#
# Every copy that shows when this runs is marked as it stands
# (`mark_shown`), in SQL and with no application class: its addresses were
# derived by the write that took it, or by the old sweep. A copy of a record
# that is still scheduled is left due, a pending change is left pending, and
# a copy of a record that is not published is left for that first refresh
# (`test/migrations/add_settled_at_to_published_versions_test.rb`).
class AddSettledAtToPublishedVersions < ActiveRecord::Migration[8.1]
  def up
    add_column :published_versions, :settled_at, :datetime
    add_index :published_versions, :live_at, where: "settled_at IS NULL", name: "index_published_versions_on_live_at_unsettled"
    mark_shown
  end

  def mark_shown
    execute(<<~SQL.squish)
      UPDATE published_versions SET settled_at = live_at
      WHERE live_at <= NOW() AND (
        (record_type = 'Page' AND record_id IN (SELECT id FROM pages WHERE published_at <= NOW())) OR
        (record_type = 'Post' AND record_id IN (SELECT id FROM posts WHERE published_at <= NOW())))
    SQL
  end

  def down
    remove_column :published_versions, :settled_at
  end
end
