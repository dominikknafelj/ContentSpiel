module Admin
  # The Tiptap editor's own image upload button (design spec §4.1/§4.2)
  # POSTs a multipart `file` straight here -- there's no page or post this
  # belongs to yet at upload time (the editor doesn't know which document
  # it'll end up referenced from until the `asset_id` it gets back is
  # inserted into one), so this is its own top-level resource, `create`
  # only, JSON in and out.
  class MediaAssetsController < BaseController
    # `params[:file]` missing entirely (no multipart part at all -- not the
    # same as an empty one, which `ActionDispatch::Http::UploadedFile`
    # would still answer to) is the one shape this can't hand straight to
    # `MediaAsset#file_is_attached` and get a normal validation error back:
    # there's nothing to `.attach`, so this reports the same "must be
    # attached" message as a matter of form rather than crash trying to
    # call `.original_filename` on `nil`.
    def create
      upload = params[:file]
      return render_errors([ "file must be attached" ]) unless upload.respond_to?(:tempfile)

      asset = MediaAsset.new(created_by: Current.user)
      asset.file.attach(io: upload.tempfile, filename: upload.original_filename, content_type: upload.content_type)

      if asset.save
        analyze_dimensions(asset)
        render json: { id: asset.id, url: asset.url }, status: :created
      else
        render_errors(asset.errors.full_messages)
      end
    end

    private

    # Dimensions come from `file.analyze`'s blob metadata (design spec
    # §4.2's "Implement" step) -- called only *after* `asset.save` above,
    # not before: `Blob#analyze` reads the blob's own bytes back off the
    # storage service (the image analyzer has to actually look at the
    # pixels), and those bytes aren't there yet until Active Storage's own
    # `after_commit` upload hook has run, which doesn't happen until this
    # record's save actually commits. Calling it any earlier is exactly the
    # "blob not yet uploaded" trap `MediaAsset#with_attachable_io`'s own
    # comment works around for content-type sniffing -- there's no
    # equivalent workaround here, since an analyzer needs the *whole* file,
    # not a quick prefix peek, so this simply waits for the real thing.
    #
    # `width`/`height` are written straight onto the already-saved row with
    # `update_columns` (no callbacks, no re-validation) rather than another
    # trip through `#cache_metadata_from_file` -- that `before_save` hook
    # already ran once, before analysis was possible, and re-triggering a
    # whole save here would re-run every validation against a record
    # nothing about has actually changed except metadata this app never
    # validates.
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
      Rails.logger.warn("[media_assets] MediaAsset##{asset.id} analysis failed: #{e.class}: #{e.message}")
    end

    def render_errors(messages)
      render json: { errors: messages }, status: :unprocessable_entity
    end
  end
end
