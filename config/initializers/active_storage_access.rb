# Final fix wave (C, P6): Active Storage's *write* endpoints require a
# signed-in user.
#
# Rails draws `POST /rails/active_storage/direct_uploads` (creates a blob
# row and hands back a signed upload URL) and `PUT
# /rails/active_storage/disk/:encoded_token` (writes the bytes, for the
# Disk service this app uses in every environment) for every app, with no
# authentication of their own. ContentSpiel never uses direct uploads --
# every upload goes through a CS Studio controller (`Admin::
# MediaAssetsController`, the settings logo, image blocks), which checks
# the file itself -- so, left alone, the two only gave a signed-out visitor
# a way to create blobs and fill storage.
#
# They're gated rather than removed (`draw_routes = false` would also take
# away `rails_blob_path` and the other `direct` routes Active Storage
# defines in the same file, which `Media::Asset#url` and the site's images
# depend on -- re-declaring those means copying Rails internals). The same
# session check CS Studio uses, answering a signed-out request with a bare
# 401 (`ActiveStorageWriteAuthentication`, which says why not a redirect).
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
# A library image's ORIGINAL is the editors' alone (image delivery spec,
# decision 2), and the public gets only the widths `Media::RenditionJob` made.
# The two blob controllers and the disk controller refuse a blob attached as
# `Media::Asset#file` to everyone (`ActiveStorageLibraryOriginalRefusal`): the
# proxy ones take no session (`ActiveStorage::DisableSession`) and cannot tell
# an editor from a visitor, so an editor downloads the original through CS
# Studio, `Admin::MediaOriginalsController`. The logo is no library image and
# stays a public original.
#
# And no request makes a variant of a library image: the two representation
# controllers answer 404 for a width that has no variant record
# (`ActiveStorageMadeVariantsOnly`), by OVERRIDING Rails' `set_representation`
# rather than following it with a callback of our own, because Rails'
# callback processes the variant inline, so one after it would come too late.
# The logo's variants keep Rails' behaviour.
#
# In `to_prepare` so a code reload in development re-applies it to the
# freshly loaded controller classes; the `include?` guards keep a repeated
# run from stacking callbacks.
Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.include(ActiveStorageWriteAuthentication) unless ActiveStorage::DirectUploadsController.include?(ActiveStorageWriteAuthentication)

  unless ActiveStorage::DiskController.include?(ActiveStorageWriteAuthentication)
    ActiveStorage::DiskController.include(ActiveStorageWriteAuthentication)
    ActiveStorage::DiskController.allow_unauthenticated_access only: :show
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
