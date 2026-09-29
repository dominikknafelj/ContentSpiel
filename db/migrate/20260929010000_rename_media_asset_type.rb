# Media library Task 1: `MediaAsset` was renamed to `Media::Asset` (the
# `media_assets` table itself is unchanged -- only the Ruby constant moved).
# `active_storage_attachments.record_type` is a plain polymorphic `belongs_to
# :record` column, freely writable (unlike the append-only `audit_events
# .subject_type`, which gets a `polymorphic_class_for` override on `Audit
# ::Event` instead, since that table can never be rewritten) -- every row
# Active Storage wrote for a `MediaAsset#file` attachment stores the class
# name literally, and would otherwise fail to resolve back to a record
# (`ActiveStorage::Attachment#record` constantizes `record_type`) the moment
# the old constant stops existing.
#
# Plain SQL, not `Media::Asset`/`ActiveStorage::Attachment`: a data
# migration shouldn't depend on the app's current model classes surviving
# unchanged for as long as this migration itself stays in history.
class RenameMediaAssetType < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE active_storage_attachments SET record_type = 'Media::Asset' WHERE record_type = 'MediaAsset'"
  end

  # The exact string this migration is about to overwrite, restored --
  # letting `db:rollback` boot against the previous code (which still
  # defines `MediaAsset`, not `Media::Asset`) after this migration runs.
  def down
    execute "UPDATE active_storage_attachments SET record_type = 'MediaAsset' WHERE record_type = 'Media::Asset'"
  end
end
