module Admin
  # Strips a blank attachment param out of a params hash before it ever
  # reaches a write service (cs-studio spec §6.1, Task 4 fix round 1).
  #
  # An autosaving form's own `FormData` (`admin--autosave`) always includes
  # *every* field in the form on *every* PATCH -- including a
  # `<input type="file">` nobody touched this round. Rack parses an
  # untouched file input as an empty string, not "this key is absent"; and
  # `has_one_attached`'s writer treats an explicit blank attachable as
  # "detach the current one" (`ActiveStorage::Attached::One#attach`), the
  # same as an editor deliberately clearing the field (media library Task 4
  # replaced that writer with `#upload_to_library` below, which would read
  # it as a file to upload). Left unguarded, that means autosaving *any
  # other* field on a record with an image would silently clear or break
  # the image the moment the form's next debounced save fires -- the blank
  # file param rides along with everything else the controller hands on.
  #
  # `fields:` names which keys are attachment columns for the caller's own
  # record (`hero_image` for a page, `image` for an image block -- upload
  # fields whose file becomes a library `Media::Asset`, see
  # `#upload_to_library`) -- "blank means leave the image alone" is the one
  # rule every such field shares, so this never needs to know anything else
  # about the record it's filtering for.
  #
  # A *real* upload is never blank (an `ActionDispatch::Http::UploadedFile`
  # has no `#empty?` of its own, so `Object#blank?`'s `!self` fallback is
  # always false for one), so this only ever drops the "nobody touched
  # this field" case -- a deliberate removal has to go through an explicit
  # signal instead (`Admin::PagesController#update`'s `remove_hero_image`),
  # never just "leave the file field blank".
  module FileParams
    def drop_blank_file_params(attributes, fields:)
      attributes.reject { |key, value| fields.include?(key.to_s) && value.blank? }
    end

    # The interim upload path for a page's hero and an image block's image
    # (media library Task 4, until Task 8's picker replaces both fields):
    # the file goes into the library through `Media::Upload` -- the one
    # upload service, with its own `media.upload` check, type sniffing and
    # `media.uploaded` event -- and the caller then sets the record's
    # reference to the new asset's id through its own save service.
    #
    # On success, returns `Media::Upload`'s own result (`record` is the new
    # asset). On failure, returns a failure Result *for `record`* (the page
    # or block the upload was for), with the upload's messages added to
    # `record.errors` under `field`, so `AutosaveResponses#autosave_stream`
    # shows them in that field's own error slot -- the caller answers with
    # it instead of saving, the same as any other failed save.
    def upload_to_library(file, record:, field:)
      # `::Media::Upload`, not bare `Media::Upload`: media library Task 7's
      # `Admin::Media` namespace (`Admin::Media::GridComponent`/
      # `DetailComponent`) shadows the top-level `Media` module for a bare
      # reference lexically nested under `Admin`, this concern included
      # (`Admin::Columns::ImageColumnComponent#thumbnail_source` has the
      # fuller explanation).
      uploaded = ::Media::Upload.call(file: file)
      return uploaded if uploaded.ok?

      if uploaded.denied?
        record.errors.add(field, "can't be uploaded without permission to upload media")
      else
        messages = uploaded.record.errors.messages_for(:file).presence || uploaded.errors
        messages.each { |message| record.errors.add(field, message) }
      end
      ApplicationService::Result.new(record: record, errors: record.errors.full_messages, denied: uploaded.denied?)
    end
  end
end
