module Admin
  # "Download original" (image delivery spec, decision 2): a library image's
  # original file, the editors' alone. The public never gets it: Active
  # Storage's blob routes refuse a library original to everyone
  # (`ActiveStorageLibraryOriginalRefusal`), because their proxy controllers
  # take no session and so cannot tell an editor from a visitor. This is the
  # one way an original is read, behind the library's own gate.
  #
  # The gate is `Admin::MediaController`'s: `media.upload`, the right that
  # opens the library (a 403 without it, before anything is looked up, so the
  # answer says nothing of which ids exist), then a KEPT image by id: a
  # trashed or missing one is the 404, as its panel is.
  #
  # Sent as an attachment, streamed from storage (`send_blob_stream`), and
  # `private, no-store`: no cache in front keeps a copy, and the browser does
  # not keep one either. Nothing is made: the original's own bytes.
  class MediaOriginalsController < BaseController
    include ActiveStorage::Streaming

    before_action -> { require_permission("media.upload") }

    def show
      asset = Media::Asset.kept.with_file.find(params[:id])
      raise ActiveRecord::RecordNotFound unless asset.file.attached?

      response.cache_control.replace(no_store: true, private: true)
      send_blob_stream asset.file.blob, disposition: :attachment
    end
  end
end
