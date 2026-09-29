module Media
  # Who may edit or delete a library image (media library design spec
  # §5.1): anyone holding `media.manage`, or the image's own uploader
  # (`created_by_id`) -- "a user can always edit or delete their own
  # uploads" -- shared by `Media::Save` and `Media::Destroy`, which each
  # call `authorize!("media.manage", ...)` themselves and fall back to
  # `#uploader_may_manage?` below.
  #
  # The uploader rule still needs `media.upload` (fail closed): ownership
  # stands in for `media.manage`, never for being a library user at all.
  # So a user whose media rights were taken away since the upload can't
  # keep editing or deleting it, and a token is judged the usual way --
  # `authorize!` is token ∩ user, so the token's own group must hold
  # `media.upload` too, and a Read-only token of the uploader can't touch
  # their images. A token is the uploader when its user is (`actor_user`).
  module Ownership
    private

    def uploader_may_manage?(asset)
      uploader = actor_user
      uploader.present? && asset.created_by_id == uploader.id && authorize!("media.upload", asset)
    end
  end
end
