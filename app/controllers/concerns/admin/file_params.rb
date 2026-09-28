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
  # same as an editor deliberately clearing the field. Left unguarded, that
  # means autosaving *any other* field on a record with an attached image
  # silently deletes the image the moment the form's next debounced save
  # fires -- the blank file param rides along with everything else a
  # service like `Pages::Save` assigns.
  #
  # `fields:` names which keys are attachment columns for the caller's own
  # record (`hero_image` for a page today; a block's own image column once
  # Task 5 reuses this) -- "blank means leave the attachment alone" is the
  # one rule every `has_one_attached` field shares, so this never needs to
  # know anything else about the record it's filtering for.
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
  end
end
