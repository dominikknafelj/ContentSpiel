module Admin
  # The one thing an autosave endpoint with a library image field (a
  # page's hero, an image block's image -- `Admin::Columns
  # ::MediaColumnComponent`) has to add to its usual response (media
  # library Task 8 fix round 1, I2): after a *refused* choice, a stream
  # that re-renders the whole field with the image actually stored.
  #
  # By the time the PATCH lands, `admin--media--field` has already swapped
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
    # The error-slot map for `autosave_stream`, minus the media field's own
    # slot unless this request acted on that field. Every autosave resends the
    # whole form and `autosave_stream` replaces each listed slot with the
    # record's current errors -- empty, for a successful save -- so a LATER
    # save of some other field (a stray second autosave a second after the
    # refusal, the next keystroke in the title) used to wipe a just-shown
    # "Hero image doesn't exist" before the editor had read it. The refused
    # choice's message must stay until the editor acts on that field, i.e.
    # sends a different image id (or clears it) than the one stored.
    #
    # `sent` is the raw param (nil when the form did not carry the field),
    # `stored_before` the record's id as loaded, before the service ran;
    # `slot` the key of the media field in `fields`.
    def without_untouched_media_slot(fields, slot, sent:, stored_before:)
      return fields if !sent.nil? && sent.to_s != stored_before.to_s

      fields.except(slot)
    end

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
