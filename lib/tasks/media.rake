namespace :media do
  # Design spec §3.2: rebuilds `media_usages` from scratch, for whenever it
  # needs to be caught up with reality outside the ordinary save/destroy
  # path that keeps it current -- after the Task 4 data migration
  # backfills `hero_media_asset_id`/`media_asset_id` for existing rows, or
  # any time the table is suspected stale (a bug, a direct SQL edit, a
  # restored backup).
  desc "Rebuild the media usage index (media_usages) from every page, block and post's current state"
  task reindex: :environment do
    Media::UsageIndex.rebuild_all
  end
end
