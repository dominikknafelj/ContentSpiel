module Media
  # Stores one uploaded image as a library `Media::Asset` (media library
  # design spec §5.1) -- every way an image enters the library goes through
  # here: the picker's header Upload (`Media::PickerComponent`, through
  # `Admin::MediaAssetsController` -- the one upload for a page's hero, an
  # image block and the Tiptap editor, which then set their reference to
  # the new asset's id like any library pick) and the Media module's own
  # multi-file upload (`Admin::MediaController#create`). It replaced the editor's original
  # `MediaAssets::Create` (media library Task 6). `file` is an uploaded file
  # (`ActionDispatch::Http::UploadedFile`, or anything with `tempfile`,
  # `original_filename` and `content_type`).
  #
  # Never deduplicated: uploading a file that's already in the library makes
  # a second asset (design spec Review Focus 1) -- only the one-off data
  # migration collapses identical files.
  #
  # Needs `media.upload`: an asset isn't attached to any page or post when
  # it's uploaded (the editor only inserts its id afterwards), so there's
  # no record to scope by. Recorded as `media.uploaded`.
  class Upload < ApplicationService
    def initialize(file:, actor: Current.actor)
      @file = file
      @actor = actor
    end

    def call
      asset = Media::Asset.new(created_by: actor_user)
      return denied("media.upload", asset) unless authorize!("media.upload", asset)
      return failure(asset, [ "file must be attached" ]) unless @file.respond_to?(:tempfile)

      asset.file.attach(io: @file.tempfile, filename: @file.original_filename, content_type: @file.content_type)

      saved = Media::Asset.transaction do
        asset.save || raise(ActiveRecord::Rollback)
        Translations::StateIndex.refresh(asset)

        record_event("media.uploaded", subject: asset, metadata: { "filename" => asset.file.filename.to_s })
        true
      end
      return failure(asset) unless saved

      success(asset)
    end
  end
end
