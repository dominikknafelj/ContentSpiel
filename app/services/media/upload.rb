module Media
  # Stores one uploaded image as a library `Media::Asset` (media library
  # design spec §5.1) -- every way an image enters the library goes through
  # here: the picker's header Upload (`Admin::Ui::MediaPickerComponent`, through
  # `Admin::MediaAssetsController` -- the one upload for a page's hero, an
  # image block and the Tiptap editor, which then set their reference to
  # the new asset's id like any library pick) and the Media module's own
  # multi-file upload (`Admin::MediaController#create`). It replaced the editor's original
  # `MediaAssets::Create`. `file` is an uploaded file
  # (`ActionDispatch::Http::UploadedFile`, or anything with `tempfile`,
  # `original_filename` and `content_type`).
  #
  # Never deduplicated: uploading a file that's already in the library makes
  # a second asset -- only the one-off data
  # migration collapses identical files.
  #
  # Needs `media.upload`: an asset isn't attached to any page or post when
  # it's uploaded (the editor only inserts its id afterwards), so there's
  # no record to scope by. Recorded as `media.uploaded`, with the `folder_id`
  # it landed in.
  #
  # `folder` is the target folder (a `Media::Folder`, or its id; nil is "Not in
  # a folder") and is a place to put the image, never a right: `media.upload`
  # alone is needed. Its row is read FOR KEY SHARE inside the upload's
  # transaction, as `Media::MoveImages` reads its target (that class's header
  # says why not FOR SHARE), so `Media::DeleteFolder` either waits for the
  # upload or runs first and the upload is refused with "That folder is gone.",
  # on `file`, storing nothing: the image never falls to the foreign key's
  # nullify.
  class Upload < ApplicationService
    def initialize(file:, folder: nil, actor: Current.actor)
      @file = file
      @folder_id = folder.respond_to?(:id) ? folder.id : folder
      @actor = actor
    end

    def call
      asset = Media::Asset.new(created_by: actor_user)
      return denied("media.upload", asset) unless authorize!("media.upload", asset)
      return failure(asset, [ "file must be attached" ]) unless @file.respond_to?(:tempfile)

      asset.file.attach(io: @file.tempfile, filename: @file.original_filename, content_type: @file.content_type)

      saved = Media::Asset.transaction do
        if @folder_id
          target = Media::Folder.lock("FOR KEY SHARE").find_by(id: @folder_id)
          next gone(asset) unless target

          asset.folder_id = target.id
        end
        asset.save || raise(ActiveRecord::Rollback)
        Translations::StateIndex.refresh(asset)

        record_event("media.uploaded", subject: asset, metadata: { "filename" => asset.file.filename.to_s, "folder_id" => asset.folder_id })
        true
      end
      return saved if saved.is_a?(Result)
      return failure(asset) unless saved

      success(asset)
    end

    private

    def gone(asset)
      asset.errors.add(:file, "That folder is gone.")
      failure(asset, asset.errors.map(&:message))
    end
  end
end
