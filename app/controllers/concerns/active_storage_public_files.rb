# What Active Storage's public read routes may serve (image delivery spec,
# decision 2), as an ALLOW-LIST that fails closed. The app has three
# attachments: the site logo (`SiteSetting#logo`), a note's files
# (`Notes::Message#files`, on a storage service of their own) and a library
# image's original (`Media::Asset#file`). Of those the public gets:
#
# - an ORIGINAL only of a blob attached as the site logo;
# - a REPRESENTATION only of the logo (made on request, as Rails does: one
#   image, made at its first view), or a width a library image's recorded
#   generation lists (`Media::Asset#served_digests`, "current" or "previous")
#   whose variant record exists, so serving it makes nothing;
# - a disk file only of one of those.
#
# Everything else is refused: a note's file, a library original, a width not
# made, and above all a blob attached to nothing. That last one is why this is
# an allow-list and not a list of what to refuse: a purge deletes the
# attachment row in its transaction and the blob only later (`purge_later`),
# while the blob's signed id is in every srcset ever published. A refusal
# decided by the attachment row would serve that original, cacheable for a
# hundred years, until the job ran, or for ever if it failed.
#
# A variation key is signed but not tied to a blob, so any published width's
# key can be replayed against the logo's signed id and makes one logo variant
# each: bounded by the keys in circulation, and only ever of the logo.
module ActiveStoragePublicFiles
  LOGO = { record_type: "SiteSetting", name: "logo" }.freeze
  LIBRARY_FILE = { record_type: "Media::Asset", name: "file" }.freeze
  VARIANT_IMAGE = { record_type: "ActiveStorage::VariantRecord", name: "image" }.freeze

  module_function

  def logo_blob_ids = ActiveStorage::Attachment.where(LOGO).select(:blob_id)

  def logo?(blob) = ActiveStorage::Attachment.exists?(**LOGO, blob_id: blob.id)

  # A width a library image that still holds this blob has recorded, by the
  # digest Rails finds its variant record by, and whose variant record exists.
  def made_width?(blob, digest)
    assets = Media::Asset.joins(:file_attachment).where(active_storage_attachments: { blob_id: blob.id })
    assets.any? { |asset| asset.served_digests.include?(digest) } && blob.variant_records.exists?(variation_digest: digest)
  end

  # A file the disk route is asked for by its stored key: the logo's original,
  # or the image of a variant record that is itself servable.
  def disk_key?(key)
    blob = ActiveStorage::Blob.find_by(key: key.to_s)
    return false if blob.nil?
    return true if logo?(blob)

    attachment = ActiveStorage::Attachment.find_by(**VARIANT_IMAGE, blob_id: blob.id)
    record = attachment && ActiveStorage::VariantRecord.find_by(id: attachment.record_id)
    return false if record.nil?

    logo?(record.blob) || made_width?(record.blob, record.variation_digest)
  end
end
