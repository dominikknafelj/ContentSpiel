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

      result = MediaAssets::Create.call(file: upload)

      if result.ok?
        render json: { id: result.record.id, url: result.record.url }, status: :created
      else
        render_errors(result.errors, status: result.denied? ? :forbidden : :unprocessable_entity)
      end
    end

    private

    # 403 for a refused upload (no `media.upload`, access-control design
    # spec §3.4), 422 for a file that isn't acceptable -- both as JSON
    # `{errors:}`, which the editor shows inline either way.
    def render_errors(messages, status: :unprocessable_entity)
      render json: { errors: messages }, status: status
    end
  end
end
