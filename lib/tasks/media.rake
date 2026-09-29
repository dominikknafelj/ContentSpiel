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

  # Task 10's own controller ruling: preprocessing at upload time (the
  # `Media::Asset` `has_one_attached :file` block's `preprocessed:` proc)
  # is best-effort -- it fires once, from Active Storage's own
  # `after_create_commit` on the attachment, the moment a file is first
  # attached. A `TransformJob` that fails (a `vips` error on a corrupt
  # upload, a queue adapter outage) or was simply never enqueued (an asset
  # attached before the preprocessed variants existed at all) leaves that
  # asset stuck with no `ActiveStorage::VariantRecord` for one or more
  # widths, and nothing re-enqueues it on its own -- `#srcset`
  # (`Media::Asset`) deliberately never triggers processing itself, only
  # ever lists what's already finished. This is the catch-up: re-enqueue
  # whichever of the four named variants (`VARIANT_WIDTHS`) a non-GIF
  # asset (`#variable_image?` -- global constraints: "GIFs get no
  # variants") is still missing a `VariantRecord` for.
  #
  # Idempotent by construction, not by tracking what it already did: it
  # only ever looks at what's actually processed (a `VariantRecord`
  # existing), so running it again after the jobs it just enqueued have
  # completed finds nothing left to enqueue. Running it again *before*
  # they've completed would enqueue the same widths a second time --
  # `ActiveStorage::TransformJob` performing twice against the same
  # variation is itself idempotent (it just finds the `VariantRecord`
  # already there the second time and returns), so a duplicate job is
  # wasted work, never a wrong result.
  desc "Enqueue any missing preprocessed image variant (w480/w960/w1600/w2400) for every non-GIF Media::Asset"
  task variants: :environment do
    enqueued = 0

    Media::Asset.with_variants.find_each do |asset|
      next unless asset.variable_image?

      blob = asset.file.blob
      processed_digests = blob.variant_records.map(&:variation_digest).to_set

      Media::Asset::VARIANT_WIDTHS.each_key do |name|
        variant = asset.file.variant(name)
        next if processed_digests.include?(variant.variation.digest)

        # The same call Active Storage's own `transform_variants_later`
        # makes at upload time (`ActiveStorage::Attachment#transform_
        # variants_later` -> `Blob#preprocessed`) -- enqueues one
        # `ActiveStorage::TransformJob` for this exact variation, rather
        # than processing it inline here and blocking the rake task (and
        # whatever cron/deploy hook runs it) on however long `vips` takes
        # across a whole library.
        blob.preprocessed(variant.variation.transformations)
        enqueued += 1
      end
    end

    puts "media:variants: enqueued #{enqueued} variant job(s)"
  end
end
