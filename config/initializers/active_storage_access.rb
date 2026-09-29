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
# public -- public pages embed those URLs.
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
end
