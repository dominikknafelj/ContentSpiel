# Media library Task 4 (design spec §3.3/§3.4): every legacy `Page
# #hero_image` and `ContentBlock#image` Active Storage attachment becomes a
# reference -- `pages.hero_media_asset_id` / `content_blocks.media_asset_id`,
# both added by Task 3's own migration -- to a `Media::Asset` that
# re-attaches the *same* blob. Nothing is copied: the asset's own `file`
# attachment row points at the blob the old attachment pointed at.
#
# Per legacy attachment, in id order:
#
# 1. Reuse an asset whose file blob has the same checksum (identical files
#    collapse into one library image -- two pages that each uploaded the
#    same hero now share one asset), including an asset that was already in
#    the library before this migration (a rich-text upload). Otherwise
#    create one on this attachment's blob, titled from its filename minus
#    the extension (`ActiveStorage::Filename#base`, the same rule `Media
#    ::Asset#set_default_title` applies to an upload).
# 2. Point the page/block at it.
# 3. Delete the old attachment row -- never the blob. A deduped duplicate's
#    blob (the second copy of an identical file) is left unattached for
#    `bin/rails media:orphans` to list and, with CONFIRM=1, purge; this
#    migration never deletes stored files.
#
# A legacy attachment whose owner (page or block) no longer exists -- an
# orphaned row left behind by a raw delete -- gets no asset: there is no
# reference to set, and an asset made for it would only be an unused
# library entry nobody uploaded. It's reported and left in place.
#
# A blob whose stored `content_type` isn't one the library accepts (`Media
# ::Asset::ALLOWED_CONTENT_TYPES` at the time of writing: png/jpeg/gif/webp
# -- a hero was never type-checked, so an SVG could be sitting there) is
# *not* migrated: the library must never hold an SVG (global constraints),
# and silently dropping someone's hero isn't acceptable either. Its
# attachment row is left in place (the model no longer reads it, but the
# blob stays owned and restorable) and the migration says so.
#
# Then the `hero`/`block_image` rows of `media_usages` are rebuilt from the
# new references (design spec §3.4 step 3) -- in SQL rather than through
# `Media::UsageIndex.rebuild_all`, since those two roles are all this
# migration can have changed (rich-text rows are untouched: nothing here
# edits a body), and a data migration mustn't depend on app models that may
# change long after it's written. The result is exactly what `UsageIndex`
# computes for those roles (the migration test checks the two agree).
#
# Plain lightweight models (`MigrationAttachment` etc. below) and SQL, not
# `Media::Asset`/`Page`: the same "don't depend on today's app classes"
# reasoning as `RenameMediaAssetType`. It also means the asset row is
# written without `Media::Asset`'s own byte-sniffing validation -- which is
# fine, because the blob's type was already checked against the allowlist
# above and its `content_type` is what the asset caches.
#
# The one step that does reach for the app is best-effort and last: queueing
# the responsive variants (`w480`..`w2400`) for each newly created asset --
# an asset made by inserting its attachment row directly never fires Active
# Storage's own `after_create_commit :transform_variants_later`, so without
# this a migrated image would serve only its original until something
# processed them. A failure there is logged, never raised: `Media::Asset
# #srcset` already serves the original alone until a variant exists.
#
# `down` (design spec §3.4: "reversible in structure") re-creates each
# page's/block's attachment on its asset's blob, clears the references and
# their usage rows. A record that `up` deduped onto another record's asset
# is restored onto that asset's (canonical) blob, not the byte-identical
# duplicate blob it had before -- that one was left unattached by `up`
# (and may have been purged by `media:orphans` since), and the bytes are
# the same.
#
# It then removes the assets `up` itself created -- their `file` attachment
# row and their own row, never the blob, which the restored attachment now
# owns alone -- and nothing else: a pre-existing library asset (a rich-text
# upload `up` deduped onto) and anything uploaded after the migration
# survive a rollback, even when a hero points at them (the restored
# attachment then shares the blob). Which assets `up` created is recorded
# in a ledger table, `media_library_migrated_assets`, created by `up` and
# dropped by `down`. A table rather than a rule like "`created_by_id IS
# NULL` and no `media.uploaded` event": assets uploaded before the audit
# log existed match that rule too, and a temporary table wouldn't survive
# from the `db:migrate` session to a later `db:rollback`. No FK on the
# ledger, so it never blocks deleting an asset in the meantime. An asset
# `up` created that rich text now also embeds (`asset_id` anywhere in a
# post's or block's body) is kept as well.
class MoveImagesIntoMediaLibrary < ActiveRecord::Migration[8.1]
  # Which legacy attachments move, and onto which reference column.
  SOURCES = [
    { record_type: "Page", name: "hero_image", table: "pages", column: "hero_media_asset_id", role: "hero" },
    { record_type: "ContentBlock", name: "image", table: "content_blocks", column: "media_asset_id", role: "block_image" }
  ].freeze

  # `Media::Asset::ALLOWED_CONTENT_TYPES` as of this migration, frozen here
  # rather than referenced, for the reason in the class comment.
  ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze

  ASSET_RECORD_TYPE = "Media::Asset".freeze

  LEDGER = :media_library_migrated_assets

  class MigrationAttachment < ActiveRecord::Base
    self.table_name = "active_storage_attachments"
  end

  class MigrationBlob < ActiveRecord::Base
    self.table_name = "active_storage_blobs"
  end

  class MigrationAsset < ActiveRecord::Base
    self.table_name = "media_assets"
  end

  def up
    create_table(LEDGER, id: false, if_not_exists: true) { |t| t.bigint :media_asset_id, null: false, index: { unique: true } }

    created_asset_ids = []
    asset_ids_by_checksum = existing_asset_ids_by_checksum

    SOURCES.each do |source|
      MigrationAttachment.where(record_type: source[:record_type], name: source[:name]).order(:id).each do |attachment|
        blob = MigrationBlob.find_by(id: attachment.blob_id)

        unless blob && ALLOWED_CONTENT_TYPES.include?(blob.content_type)
          reason = blob ? "#{blob.filename} is #{blob.content_type}, which the media library doesn't accept" : "blob #{attachment.blob_id} is missing"
          say "Skipped #{source[:record_type]}##{attachment.record_id} #{source[:name]}: #{reason} (attachment left in place)"
          next
        end

        unless select_value(sanitize("SELECT 1 FROM #{source[:table]} WHERE id = ?", attachment.record_id))
          say "Skipped #{source[:record_type]}##{attachment.record_id} #{source[:name]}: the #{source[:record_type]} no longer exists (attachment left in place)"
          next
        end

        # A blob with no checksum (Active Storage allows one) is never
        # deduped: `nil` would otherwise collapse every such blob into one.
        asset_id = asset_ids_by_checksum[blob.checksum] if blob.checksum.present?
        unless asset_id
          asset_id = create_asset(blob, created_at: attachment.created_at)
          execute sanitize("INSERT INTO #{LEDGER} (media_asset_id) VALUES (?)", asset_id)
          asset_ids_by_checksum[blob.checksum] = asset_id if blob.checksum.present?
          created_asset_ids << asset_id
        end

        execute sanitize("UPDATE #{source[:table]} SET #{source[:column]} = ? WHERE id = ?", asset_id, attachment.record_id)
        attachment.delete
        say "#{source[:record_type]}##{attachment.record_id} #{source[:name]} (#{blob.filename}) -> Media::Asset##{asset_id}"
      end
    end

    rebuild_usages
    say "Created #{created_asset_ids.size} media asset(s)"
    enqueue_variants(created_asset_ids)
  end

  def down
    restored_asset_ids = []

    SOURCES.each do |source|
      rows = select_rows("SELECT id, #{source[:column]} FROM #{source[:table]} WHERE #{source[:column]} IS NOT NULL ORDER BY id")
      rows.each do |record_id, asset_id|
        file = MigrationAttachment.find_by(record_type: ASSET_RECORD_TYPE, record_id: asset_id, name: "file")
        if file
          MigrationAttachment.create!(record_type: source[:record_type], record_id: record_id, name: source[:name], blob_id: file.blob_id, created_at: Time.current)
          restored_asset_ids << asset_id
        end
        execute sanitize("UPDATE #{source[:table]} SET #{source[:column]} = NULL WHERE id = ?", record_id)
      end
    end

    execute "DELETE FROM media_usages WHERE role IN ('hero', 'block_image')"

    migrated = table_exists?(LEDGER) ? select_values("SELECT media_asset_id FROM #{LEDGER}").map(&:to_i) : []
    restored = restored_asset_ids.uniq
    embedded = rich_text_asset_ids
    removable = (restored & migrated) - embedded

    (restored - removable).each do |id|
      reason = migrated.include?(id) ? "rich text still embeds it" : "the migration didn't create it"
      say "Kept Media::Asset##{id}: #{reason} (its blob is now shared with the restored attachment)"
    end

    if removable.any?
      execute sanitize("DELETE FROM media_usages WHERE media_asset_id IN (?)", removable)
      MigrationAttachment.where(record_type: ASSET_RECORD_TYPE, record_id: removable, name: "file").delete_all
      MigrationAsset.where(id: removable).delete_all
      say "Removed #{removable.size} media asset(s)"
    end

    drop_table LEDGER, if_exists: true
  end

  private

  def sanitize(sql, *values) = ActiveRecord::Base.sanitize_sql_array([ sql, *values ])

  # Checksum -> asset id for every asset already in the library, first
  # (lowest id) wins when two library uploads were themselves identical.
  def existing_asset_ids_by_checksum
    rows = select_rows(<<~SQL)
      SELECT blobs.checksum, attachments.record_id
      FROM active_storage_attachments attachments
      JOIN active_storage_blobs blobs ON blobs.id = attachments.blob_id
      WHERE attachments.record_type = '#{ASSET_RECORD_TYPE}' AND attachments.name = 'file'
      ORDER BY attachments.record_id
    SQL
    rows.each_with_object({}) { |(checksum, asset_id), map| map[checksum] ||= asset_id if checksum.present? }
  end

  # The asset row plus its `file` attachment on the very same blob. Width
  # and height come from the blob's own analyzer metadata when it has any
  # (a legacy attachment was analyzed on upload); nil otherwise, the same
  # "may be nil" allowance `Media::Upload#analyze_dimensions` makes.
  def create_asset(blob, created_at:)
    metadata = blob.metadata.present? ? JSON.parse(blob.metadata) : {}
    asset = MigrationAsset.create!(
      title: ActiveStorage::Filename.new(blob.filename).base,
      content_type: blob.content_type,
      byte_size: blob.byte_size,
      width: metadata["width"],
      height: metadata["height"],
      created_at: created_at,
      updated_at: Time.current
    )
    MigrationAttachment.create!(record_type: ASSET_RECORD_TYPE, record_id: asset.id, name: "file", blob_id: blob.id, created_at: created_at)
    asset.id
  end

  def rebuild_usages
    execute "DELETE FROM media_usages WHERE role IN ('hero', 'block_image')"

    SOURCES.each do |source|
      execute <<~SQL
        INSERT INTO media_usages (media_asset_id, owner_type, owner_id, role, locale, created_at, updated_at)
        SELECT #{source[:column]}, '#{source[:record_type]}', id, '#{source[:role]}', NULL, now(), now()
        FROM #{source[:table]}
        WHERE #{source[:column]} IS NOT NULL
        ON CONFLICT DO NOTHING
      SQL
    end
  end

  # Every `asset_id` value anywhere in a post's or block's per-locale body
  # documents -- only a rich-text `image` node carries that attribute
  # (`RichText::BuiltIns`). Stored as an integer by the editor, but a String
  # from an older import is normalised the same way.
  def rich_text_asset_ids
    %w[posts content_blocks].flat_map do |table|
      select_values(<<~SQL)
        SELECT DISTINCT value #>> '{}'
        FROM #{table}, jsonb_path_query(#{table}.body, 'lax $.**.asset_id') AS value
      SQL
    end.filter_map { |value| Integer(value, exception: false) }.uniq
  end

  # In its own savepoint (fix round 1, M4): the rescue below is only safe
  # if a database error raised in here can't leave the migration's own
  # transaction aborted ("current transaction is aborted, commands ignored
  # until end of transaction block") -- rolling back to the savepoint
  # first, before the rescue runs, keeps the data changes above intact.
  def enqueue_variants(asset_ids)
    return if asset_ids.empty?

    ActiveRecord::Base.transaction(requires_new: true) do
      Media::Asset.where(id: asset_ids).find_each do |asset|
        Media::Asset.reflect_on_attachment(:file).named_variants.each_value do |variant|
          ActiveStorage::TransformJob.perform_later(asset.file.blob, variant.transformations) if variant.preprocessed?(asset)
        end
      end
    end
  rescue StandardError => e
    say "Couldn't queue image variants (#{e.class}: #{e.message}) -- pages serve the originals until they're processed"
  end
end
