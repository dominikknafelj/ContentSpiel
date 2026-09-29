module Admin
  # The Tiptap editor's own image upload button (design spec §4.1/§4.2)
  # POSTs a multipart `file` straight here -- there's no page or post this
  # belongs to yet at upload time (the editor doesn't know which document
  # it'll end up referenced from until the `asset_id` it gets back is
  # inserted into one), so this is its own top-level resource, `create`
  # only, JSON in and out. Task 7's Media module (`Admin::MediaController`,
  # `resources :media`) is the library's own browse/edit/delete home, but
  # this controller keeps its own separate route and its own narrower
  # `{id, url}`/`{errors}` JSON contract rather than folding into it --
  # `admin--rich-text` and `admin--media-upload` are two unrelated callers
  # that happen to share the same underlying `Media::Upload`, not one
  # feature split across two endpoints.
  class MediaAssetsController < BaseController
    # `params[:file]` missing entirely (no multipart part at all -- not the
    # same as an empty one, which `ActionDispatch::Http::UploadedFile`
    # would still answer to) is the one shape this can't hand straight to
    # `Media::Asset#file_is_attached` and get a normal validation error back:
    # there's nothing to `.attach`, so this reports the same "must be
    # attached" message as a matter of form rather than crash trying to
    # call `.original_filename` on `nil`.
    def create
      upload = params[:file]
      return render_errors([ "file must be attached" ]) unless upload.respond_to?(:tempfile)

      # `::Media::Upload`, not bare `Media::Upload`: `Admin::Media
      # ::GridComponent`/`DetailComponent` (Task 7) made `Admin::Media` a
      # real namespace, which shadows the top-level `Media` module for
      # every bare `Media::` reference lexically nested under `Admin` --
      # this controller's own included. Left bare, this would resolve to
      # (nonexistent) `Admin::Media::Upload`.
      result = ::Media::Upload.call(file: upload)

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
