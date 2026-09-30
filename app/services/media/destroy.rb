module Media
  # Deletes a library image (media library design spec §5.1). Cleanup is
  # manual only, and an image in use is never deleted:
  #
  # - Refused while any `media_usages` row names it, with a message saying
  #   where it's used (`Media::Asset#in_use_message`) so the editor can go and swap it
  #   out first.
  # - The index can be behind -- a reference written outside the services,
  #   or a save racing this delete between the check and the `DELETE`
  #   (Review Focus 4). The FKs on `pages`/
  #   `content_blocks` still refuse the row, and that
  #   `ActiveRecord::InvalidForeignKey` becomes an ordinary failure here,
  #   never a 500. (A rich-text `image` node has no FK -- a document that
  #   still names a deleted asset renders without it, and `Media::
  #   UsageIndex` skips the dead reference.)
  #
  # Needs `media.manage`, or to be the image's uploader (`Media::
  # Ownership`). `media.deleted` is recorded before the destroy, in its
  # transaction, so the snapshot is the asset's last state and a refused
  # destroy leaves no event.
  #
  # The file itself is purged only after the delete commits: `has_one_
  # attached`'s default `dependent: :purge_later` enqueues the purge from
  # an `after_destroy_commit`, so a rolled-back delete (the FK case above)
  # keeps its file, and storage isn't touched inside the transaction.
  class Destroy < ApplicationService
    include Ownership

    def initialize(asset, actor: Current.actor)
      @asset = asset
      @actor = actor
    end

    def call
      return denied("media.manage", @asset) unless authorize!("media.manage", @asset) || uploader_may_manage?(@asset)
      return failure(@asset, [ @asset.in_use_message(actor:) ]) if @asset.used?

      destroyed = Media::Asset.transaction(requires_new: true) do
        record_event("media.deleted", subject: @asset)
        @asset.destroy || raise(ActiveRecord::Rollback)
      end

      # A destroy halted by a callback may add no error of its own (final
      # fix wave, T6b) -- `Result.failure`'s generic fallback would then
      # say "could not be saved", which is the wrong verb here.
      return failure(@asset, @asset.errors.full_messages.presence || [ "This image couldn't be deleted" ]) unless destroyed

      success(@asset)
    rescue ActiveRecord::InvalidForeignKey
      failure(@asset, [ "This image is still in use and can't be deleted" ])
    end
  end
end
