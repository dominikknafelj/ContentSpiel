module Admin
  # The one thing an autosave endpoint with a library image field (a
  # page's hero, an image block's image -- `Admin::Columns
  # ::MediaColumnComponent`) has to add to its usual response (media
  # library Task 8 fix round 1, I2): after a *refused* choice, a stream
  # that re-renders the whole field with the image actually stored.
  #
  # By the time the PATCH lands, `admin--media-field` has already swapped
  # the thumbnail, the title, the Change/Choose label and the override
  # fields' placeholders over to the picked image, and put its id in the
  # hidden input. Left like that, the field shows an image that was never
  # saved, and -- since autosave resends every field on every save -- each
  # later autosave would send the refused id again and fail again. The
  # re-rendered field carries the stored id (so the next autosave is a
  # no-op for it), the stored image, and the refusal's message in its own
  # error slot; its controller restores the override placeholders on
  # connect (`MediaColumnComponent#defaults`).
  #
  # "Refused" means the choice itself was the problem: the save failed with
  # an error on the field (`Media::Choosing`'s "doesn't exist" -- a forged
  # id, or an image deleted between opening the picker and picking), or it
  # was denied (no `media.upload`; any denial saves nothing, so the stored
  # image is the right thing to show either way) -- and the request
  # actually tried to change the image. A save that failed only because of
  # some *other* field leaves a valid pick alone, to be resent with the
  # next autosave like any other unsaved field.
  #
  # Appended *after* `autosave_stream`'s own error-slot replacements: the
  # error slot lives inside the re-rendered section, so this replace is
  # what finally shows the message (rendered by the component itself).
  module MediaFields
    private

    # `sent` is the raw param (nil when the request didn't carry it);
    # `build` yields the stored asset and the field's errors and returns
    # the component to render.
    def refused_media_field_stream(result, attribute:, error_attribute:, sent:)
      return if result.ok? || sent.nil?

      record = result.record
      stored_id = record.attribute_in_database(attribute.to_s)
      return if sent.to_s == stored_id.to_s
      return unless result.denied? || record.errors.include?(error_attribute)

      stored = stored_id && Media::Asset.with_variants.find_by(id: stored_id)
      component = yield(stored, record.errors.full_messages_for(error_attribute))
      turbo_stream.replace(component.section_dom_id, component)
    end
  end
end
