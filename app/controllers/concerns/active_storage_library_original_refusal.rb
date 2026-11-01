# For Active Storage's blob READ controllers and its disk controller
# (config/initializers/active_storage_access.rb; image delivery spec,
# decision 2): a library image's ORIGINAL is the editors' alone. The public
# gets only the widths `Media::RenditionJob` made, re-encoded with camera data
# dropped, through the representation proxy. These controllers serve any blob
# to whoever holds its signed id or disk key, and the proxy ones take no
# session (`ActiveStorage::DisableSession`), so they cannot tell an editor from
# a visitor: they refuse a library original to everyone, and an editor
# downloads it through CS Studio (`Admin::MediaOriginalsController`).
#
# A library original is a blob attached as `Media::Asset#file`. The logo and
# every other attachment are served as before.
#
# Two shapes of the same refusal, as `ActiveStorageNoteFilesRefusal`'s:
# - the blob controllers find their blob by signed id through `blob_scope`
#   (`ActiveStorage::SetBlob`), which here leaves the library's files out: the
#   blob is not found, a 404, in the one statement that finds it;
# - the disk controller's `show` is handed a signed key, and a key that names
#   a library original's blob is a 404. A made width's key is the variant's
#   own (`variants/<blob key>/<digest>`), never the blob's, so the
#   representation redirect's disk URL still answers.
#
# A refusal is a bare 404 from a `before_action`, before `http_cache_forever`
# runs, so it carries no `Cache-Control: public`.
module ActiveStorageLibraryOriginalRefusal
  extend ActiveSupport::Concern

  included do
    before_action :refuse_library_original_key
  end

  def self.library_blob_ids = ActiveStorage::Attachment.where(record_type: "Media::Asset", name: "file").select(:blob_id)

  private

  def blob_scope = super.where.not(id: ActiveStorageLibraryOriginalRefusal.library_blob_ids)

  def refuse_library_original_key
    return if params[:encoded_key].blank?

    key = ActiveStorage.verifier.verified(params[:encoded_key], purpose: :blob_key)
    return unless key.is_a?(Hash)

    blob_key = key.with_indifferent_access[:key].to_s
    head :not_found if ActiveStorage::Blob.where(key: blob_key, id: ActiveStorageLibraryOriginalRefusal.library_blob_ids).exists?
  end
end
