# For Active Storage's blob READ controllers and its disk controller
# (config/initializers/active_storage_access.rb; image delivery spec,
# decision 2): no original is public but the site logo's
# (`ActiveStoragePublicFiles`, an allow-list that fails closed). A library
# image's original is the editors' alone, downloaded through CS Studio
# (`Admin::MediaOriginalsController`): these controllers serve any blob to
# whoever holds its signed id or disk key, and the proxy ones take no session
# (`ActiveStorage::DisableSession`), so they cannot tell an editor from a
# visitor. A blob attached to nothing (a purged image's, before its
# `purge_later` has run) is refused like every other.
#
# Two shapes of the same refusal, as `ActiveStorageNoteFilesRefusal`'s:
# - the blob controllers find their blob by signed id through `blob_scope`
#   (`ActiveStorage::SetBlob`), which here holds the logo's blobs alone: any
#   other blob is not found, a 404, in the one statement that finds it;
# - the disk controller's `show` is handed a signed key, and a key that is not
#   the logo's or a servable width's file is a 404 (the representation
#   redirect sends a made width's request there).
#
# A refusal is a bare 404 from a `before_action`, before `http_cache_forever`
# runs, so it carries no `Cache-Control: public`.
module ActiveStorageLibraryOriginalRefusal
  extend ActiveSupport::Concern

  included do
    before_action :refuse_unlisted_disk_key
  end

  private

  def blob_scope = super.where(id: ActiveStoragePublicFiles.logo_blob_ids)

  def refuse_unlisted_disk_key
    return if params[:encoded_key].blank?

    key = ActiveStorage.verifier.verified(params[:encoded_key], purpose: :blob_key)
    return if key.is_a?(Hash) && ActiveStoragePublicFiles.disk_key?(key.with_indifferent_access[:key])

    head :not_found
  end
end
