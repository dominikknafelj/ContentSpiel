# Active Storage's *write* endpoints answer 404 to everyone.
#
# Rails draws `POST /rails/active_storage/direct_uploads` (creates a blob
# row and hands back a signed upload URL) and `PUT
# /rails/active_storage/disk/:encoded_token` (writes the bytes, for the
# Disk service this app uses in every environment) for every app, with no
# authentication of their own. ContentSpiel never uses direct uploads --
# every upload goes through a CS Studio controller (`Admin::
# MediaAssetsController`, the settings logo, image blocks), which checks
# the file itself -- so the two are surface with no use, and a session that
# could create orphan blobs through them would be one more door.
#
# They're refused rather than removed (`draw_routes = false` would also take
# away `rails_blob_path` and the other `direct` routes Active Storage
# defines in the same file, which `Media::Asset#url` and the site's images
# depend on -- re-declaring those means copying Rails internals). Each
# answers a bare 404 and reads no session (`ActiveStorageWriteRefusal`).
# The *read* side (blob redirects, representations, `GET /disk/...`) stays
# public -- public pages embed those URLs -- but for the blobs below.
#
# One kind of blob is NOT public on the read side (notes spec D15): the files
# of notes, which live on a storage service of their own (`notes`,
# `config/storage.yml`). Every read controller refuses a blob of that service
# (`ActiveStorageNoteFilesRefusal`); a note's file is read only through
# `Admin::NoteFilesController`. The concern goes into each concrete
# controller, not their base classes: a callback added to a parent after its
# child was loaded does not reach the child.
#
# What else the read routes serve is an ALLOW-LIST that fails closed
# (`ActiveStoragePublicFiles`, which says why: a purged image's blob outlives
# its attachment row). The two blob controllers and the disk controller serve
# an original only of the site logo (`ActiveStorageLibraryOriginalRefusal`): a
# library image's original is the editors' alone, downloaded through CS Studio
# (`Admin::MediaOriginalsController`), because the proxy controllers take no
# session (`ActiveStorage::DisableSession`) and cannot tell an editor from a
# visitor. The two representation controllers serve only a width a library
# image's generation records and has made, or a logo variant
# (`ActiveStorageMadeVariantsOnly`), by OVERRIDING Rails' `set_representation`
# rather than following it with a callback of our own, because Rails'
# callback processes the variant inline, so one after it would come too late.
# Only the logo's variants are made on request.
#
# In `to_prepare` so a code reload in development re-applies it to the
# freshly loaded controller classes; the `include?` guards keep a repeated
# run from stacking callbacks.
Rails.application.config.to_prepare do
  [ ActiveStorage::DirectUploadsController, ActiveStorage::DiskController ].each do |controller|
    controller.include(ActiveStorageWriteRefusal) unless controller.include?(ActiveStorageWriteRefusal)
  end

  [ ActiveStorage::Blobs::RedirectController, ActiveStorage::Blobs::ProxyController, ActiveStorage::Representations::RedirectController,
    ActiveStorage::Representations::ProxyController, ActiveStorage::DiskController ].each do |controller|
    controller.include(ActiveStorageNoteFilesRefusal) unless controller.include?(ActiveStorageNoteFilesRefusal)
  end

  [ ActiveStorage::Blobs::RedirectController, ActiveStorage::Blobs::ProxyController, ActiveStorage::DiskController ].each do |controller|
    controller.include(ActiveStorageLibraryOriginalRefusal) unless controller.include?(ActiveStorageLibraryOriginalRefusal)
  end

  [ ActiveStorage::Representations::RedirectController, ActiveStorage::Representations::ProxyController ].each do |controller|
    controller.include(ActiveStorageMadeVariantsOnly) unless controller.include?(ActiveStorageMadeVariantsOnly)
  end
end
