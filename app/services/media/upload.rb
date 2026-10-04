module Media
  # Stores one uploaded image as a library `Media::Asset` (media library
  # design spec §5.1) -- every way an image enters the library goes through
  # here: the picker's Upload tab (`Media::PickerComponent`, through
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

      analyze_dimensions(asset)
      success(asset)
    end

    private

    # Dimensions come from `file.analyze`'s blob metadata (design spec
    # §4.2's "Implement" step) -- called only *after* the save above has
    # committed, not before: `Blob#analyze` reads the blob's own bytes back
    # off the storage service (the image analyzer has to actually look at
    # the pixels), and those bytes aren't there yet until Active Storage's
    # own `after_commit` upload hook has run, which doesn't happen until
    # this record's save actually commits. Calling it any earlier is
    # exactly the "blob not yet uploaded" trap `Media::Asset#with_attachable_
    # io`'s own comment works around for content-type sniffing -- there's
    # no equivalent workaround here, since an analyzer needs the *whole*
    # file, not a quick prefix peek, so this simply waits for the real
    # thing.
    #
    # `width`/`height` are written straight onto the already-saved row with
    # `update_columns` (no callbacks, no re-validation) rather than another
    # trip through `#cache_metadata_from_file` -- that `before_save` hook
    # already ran once, before analysis was possible, and re-triggering a
    # whole save here would re-run every validation against a record
    # nothing about has actually changed except metadata this app never
    # validates. Derived data, not an edit, so it isn't audited.
    #
    # Wrapped in a rescue (design spec §4.2/§7: "may be nil in tests,
    # that's fine" -- and, per that same easygoing posture, in production
    # too): a content type `ALLOWED_CONTENT_TYPES` accepts but this
    # server's own `image_processing`/`ruby-vips` stack can't decode for
    # some reason must not turn an otherwise-successful upload into a 500;
    # the asset is already saved and perfectly usable with no dimensions.
    def analyze_dimensions(asset)
      asset.file.analyze
      metadata = asset.file.blob.metadata || {}
      asset.update_columns(width: metadata["width"], height: metadata["height"])
    rescue StandardError => e
      Rails.logger.warn("[media] Media::Asset##{asset.id} analysis failed: #{e.class}: #{e.message}")
    end
  end
end
