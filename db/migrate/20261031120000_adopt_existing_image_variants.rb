# An existing site's library images keep the widths they already had through
# the deploy. Before this, each still image (not a GIF) was preprocessed into
# four named variants, `resize_to_limit: [w, nil], format: :webp` for w in 480,
# 960, 1600 and 2400, and a page listed each one that was processed and
# narrower than the original. That is what is adopted here, written as the
# first generation of each image (`renditions["current"]`), with nothing made
# and nothing downloaded: the page names the same variation keys as before, so
# a cached page and a visitor's browser cache keep finding their files.
#
# The transformations are written out here and never read from the model,
# which no longer declares them.
#
# THE DIGEST. A generation records each width's variation digest as a request
# computes it (`blob.variant(key).variation.digest`, which decodes the signed
# key): the public route serves a width only when that digest is recorded and
# its variant record exists (`ActiveStoragePublicFiles`). A key decodes the
# Symbol `:webp` the preprocessing used as the String "webp", and the digest is
# a Marshal dump, which tells the two apart, so the preprocessed record was
# never found by a request. Its digest is rewritten to the request's here (the
# file is the same: libvips is handed the same format either way). A width a
# request had already made again under the request's digest keeps that record,
# and the preprocessed one is left as it is (no page names it; `media:orphans`
# never sees it, since a variant's blob is attached to its record).
#
# THE FINGERPRINT (Ruling 11). These widths were made without `strip`, and a
# JPEG carrying GPS keeps its camera data in them (checked with libvips 8.18:
# `exif-data` and the `exif-ifd3-GPS*` fields are in the old width;
# `test/migrations/adopt_existing_image_variants_test.rb` checks it again). So
# the generation is recorded under the fingerprint "adopted", which no settings
# produce: the image counts as made with other settings, and the next
# `Media::RenditionJob` (the backfill queues one for every image without a
# preview) makes it again, keeping this generation as the previous one, which
# pages cached before still find.
#
# A new database loads db/schema.rb and has no image to adopt.
class AdoptExistingImageVariants < ActiveRecord::Migration[8.1]
  OLD_WIDTHS = [ 480, 960, 1600, 2400 ].freeze
  FINGERPRINT = "adopted"
  MISSING_DECODE_INDEX = "index_media_assets_missing_decode"

  class Asset < ActiveRecord::Base
    self.table_name = "media_assets"
  end

  def up
    # What `Media::BackfillJob` asks every ten minutes, answered from the index
    # alone on a site where nothing is missing.
    add_index :media_assets, :id, name: MISSING_DECODE_INDEX,
      where: "trashed_at IS NULL AND renditions_failed_at IS NULL AND (preview IS NULL OR width IS NULL)" # sql: a partial index's predicate
    adopt
  end

  def down
    forget
    remove_index :media_assets, name: MISSING_DECODE_INDEX
  end

  def self.old_transformations(width) = { resize_to_limit: [ width, nil ], format: :webp }

  def adopt
    Asset.where(renditions_fingerprint: nil).where.not(content_type: "image/gif").find_each do |asset|
      next if asset.renditions.present?

      blob = blob_of(asset)
      next if blob.nil?

      files = OLD_WIDTHS.filter_map do |width|
        next if asset.width.present? && width >= asset.width

        adopted_file(blob, width)
      end
      next if files.empty?

      asset.update_columns( # version: none (the same widths the page already named)
        renditions: { "current" => { "fingerprint" => FINGERPRINT, "files" => files } },
        renditions_fingerprint: FINGERPRINT
      )
    end
  end

  # The adopted rows are emptied, and a preprocessed record whose digest was
  # rewritten gets its old one back, where no record holds that digest.
  def forget
    Asset.where(renditions_fingerprint: FINGERPRINT).find_each do |asset|
      blob = blob_of(asset)
      Array(asset.renditions.dig("current", "files")).each do |file|
        next if blob.nil?

        old_digest = blob.variant(self.class.old_transformations(file["width"].to_i)).variation.digest
        next if ActiveStorage::VariantRecord.exists?(blob_id: blob.id, variation_digest: old_digest)

        ActiveStorage::VariantRecord.where(blob_id: blob.id, variation_digest: file["digest"]).update_all(variation_digest: old_digest)
      end
      asset.update_columns(renditions: {}, renditions_fingerprint: nil) # version: none (the widths go back to the variants the old code reads)
    end
  end

  private

  def blob_of(asset)
    attachment = ActiveStorage::Attachment.find_by(record_type: "Media::Asset", record_id: asset.id, name: "file")
    attachment && ActiveStorage::Blob.find_by(id: attachment.blob_id)
  end

  # The width as a request finds it, or nil when it was never processed.
  def adopted_file(blob, width)
    preprocessed = blob.variant(self.class.old_transformations(width)).variation
    key = preprocessed.key
    digest = blob.variant(key).variation.digest
    records = ActiveStorage::VariantRecord.where(blob_id: blob.id)

    unless records.exists?(variation_digest: digest)
      return nil unless records.exists?(variation_digest: preprocessed.digest)

      records.where(variation_digest: preprocessed.digest).update_all(variation_digest: digest)
    end
    { "width" => width, "key" => key, "digest" => digest }
  end
end
