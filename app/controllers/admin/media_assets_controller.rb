module Admin
  # `Media::PickerComponent`'s header Upload (media library Task 8, round 3 Task 9 -- the one
  # way to upload from a hero field, an image block or the Tiptap editor's
  # Image button, which used to POST here directly) POSTs a multipart
  # `file` straight here -- there's no page or post this belongs to yet at
  # upload time (the picker doesn't know which field or document the id it
  # gets back will end up in), so this is its own top-level resource, `create`
  # only, JSON in and out. Task 7's Media module (`Admin::MediaController`,
  # `resources :media`) is the library's own browse/edit/delete home, but
  # this controller keeps its own separate route and its own narrower
  # JSON contract (`Admin::MediaUploadResponses`: `id`, `title`, `url`, the finished
  # pick tile and the counts, or `{errors}`) rather than folding into it --
  # `admin--media--picker` and `admin--media--upload` are two unrelated callers
  # that happen to share the same underlying `Media::Upload`, not one
  # feature split across two endpoints.
  class MediaAssetsController < BaseController
    include MediaUploadResponses

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

      result = Media::Upload.call(file: upload)

      if result.ok?
        render json: upload_json(result.record, picker: true), status: :created
      else
        render_errors(result.errors, status: result.denied? ? :forbidden : :unprocessable_entity)
      end
    end

    private

    # 403 for a refused upload (no `media.upload`, access-control design
    # spec §3.4), 422 for a file that isn't acceptable -- both as JSON
    # `{errors:}`, which the picker shows inline either way. `title` on
    # success is what the picker hands on with the new id (the same
    # `{id, url, title}` a Library-tab pick carries).
    def render_errors(messages, status: :unprocessable_entity)
      render json: { errors: messages }, status: status
    end
  end
end
