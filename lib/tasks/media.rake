namespace :media do
  # Design spec §3.2: rebuilds `media_usages` from scratch, for whenever it
  # needs to be caught up with reality outside the ordinary save/destroy
  # path that keeps it current -- after the Task 4 data migration
  # backfills `hero_media_asset_id`/`media_asset_id` for existing rows, or
  # any time the table is suspected stale (a bug, a direct SQL edit, a
  # restored backup).
  desc "Rebuild the media usage index (media_usages) from every page, block and post's current state"
  task reindex: :environment do
    failures = Media::UsageIndex.rebuild_all

    if failures.positive?
      puts "media:reindex: #{failures} owner(s) failed to index -- see the Rails log for details"
    else
      puts "media:reindex: rebuilt cleanly"
    end
  end

  # Design spec §3.4 step 5: every `ActiveStorage::Blob` no attachment row
  # points at -- a duplicate file the Task 4 data migration deduped onto
  # another asset (it deletes attachment rows, never blobs), a leftover
  # from the ActionText import, a blob whose record was deleted without its
  # purge job ever running. Cleanup is manual only (global constraints):
  # without CONFIRM=1 this only lists them; with it, each is purged (its
  # stored file and its row, plus any variants Active Storage made of it).
  #
  # A variant's own blob is attached to its `ActiveStorage::VariantRecord`
  # (`image`), so it never shows up here while the variant exists.
  desc "List blobs with no attachments (media library cleanup); CONFIRM=1 purges them"
  task orphans: :environment do
    orphans = ActiveStorage::Blob.where.missing(:attachments).order(:id)
    confirmed = ENV["CONFIRM"] == "1"

    count = 0
    purged = 0
    failed = 0
    orphans.find_each do |blob|
      count += 1
      puts "  blob ##{blob.id}  #{blob.filename}  #{blob.content_type}  #{blob.byte_size} bytes  created #{blob.created_at.iso8601}"
      next unless confirmed

      # Counted as purged only once the row is confirmed gone (fix round 1,
      # M5) -- a purge that raised, or one a concurrent attach raced, is
      # reported instead of silently counted.
      begin
        blob.purge
      rescue StandardError => e
        puts "    purge failed: #{e.class}: #{e.message}"
      end
      if ActiveStorage::Blob.exists?(blob.id)
        failed += 1
      else
        purged += 1
      end
    end

    if confirmed
      puts "media:orphans: purged #{purged} blob(s)#{", #{failed} could not be purged" if failed.positive?}"
    else
      puts "media:orphans: #{count} blob(s) with no attachments#{" -- run with CONFIRM=1 to purge them" if count.positive?}"
    end
  end
end
