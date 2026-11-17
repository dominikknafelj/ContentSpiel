# Who published a version, as the History screen says it (the StudioHistory
# card, "A version row"): a person; "Published by a removed account" when
# the publisher's account was deleted since; "Published by the system" when
# nobody was behind it (the console, a seed, `bin/load`); "Kept when history
# began" for the copies `CreatePublishedVersions` made of what was live when
# history was switched on, and no other.
#
# Two things the table could not tell until now, so this migration keeps
# them:
#
# - THE PUBLISHER'S ID OUTLIVES THE ACCOUNT. The foreign key nullified
#   `created_by_id` when a user was deleted, which made a removed account's
#   version read as nobody's. Without the key the id stays, as
#   `audit_events.user_id` keeps an actor's (which has no key either): an id
#   whose user is gone is a removed account. Ids are never given out again
#   (a bigint sequence), so a stale id never names a new person.
# - THE MIGRATION'S COPIES ARE MARKED (`kept_when_history_began`). What that
#   migration wrote is a copy numbered 1 with no publisher, which is also what
#   `Publishing::Version.take!` writes for a publish with nobody behind it, so
#   the History screen once read every first copy without a publisher as kept
#   when history began, a seed's of yesterday included.
#
# The mark is written once, here (`mark_first_copies`), in SQL and with no
# application class: the copies that migration made are the first rows of the
# table, taken before any publish a person made, so a copy numbered 1 with no
# publisher whose id is below every copy that has a publisher or a number
# above 1 is one of them. On a database the old migration found nothing to
# copy on (every new site) it marks nothing. A version a removed account
# published before this ran has lost its id to the old key, and reads as the
# system's.
class KeepVersionPublishers < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :published_versions, :users, column: :created_by_id
    add_column :published_versions, :kept_when_history_began, :boolean, null: false, default: false
    mark_first_copies
  end

  # Public so that the test can run it.
  def mark_first_copies
    execute(<<~SQL.squish)
      UPDATE published_versions SET kept_when_history_began = TRUE
      WHERE number = 1 AND created_by_id IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM published_versions AS earlier
          WHERE earlier.id < published_versions.id AND (earlier.created_by_id IS NOT NULL OR earlier.number > 1))
    SQL
  end

  def down
    remove_column :published_versions, :kept_when_history_began
    execute("UPDATE published_versions SET created_by_id = NULL WHERE created_by_id NOT IN (SELECT id FROM users)")
    add_foreign_key :published_versions, :users, column: :created_by_id, on_delete: :nullify
  end
end
