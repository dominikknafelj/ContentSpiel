module Media
  # Pointing a page's hero (`pages.hero_media_asset_id`) or an image block
  # (`content_blocks.media_asset_id`) at a library image (media library
  # design spec §5.1, Review Focus 5), shared by `Pages::Save` and
  # `ContentBlocks::Save`, which call `#media_choice_result` after their own
  # edit checks and before assigning anything:
  #
  # - Choosing an image -- a present value that differs from the stored
  #   one -- needs `media.upload` (the "choose images" half of that
  #   permission): a user who can edit a page but not use the library
  #   can't forge an id in. Clearing it (nil or blank) and resending the
  #   stored id need nothing beyond the edit right the service already
  #   checked.
  # - The id must name an existing asset. Without this check a forged id
  #   would reach Postgres as an `on_delete: :restrict` FK violation --
  #   a 500 -- and a non-numeric one would be cast to nil, silently
  #   clearing the image instead. It's refused as a validation failure on
  #   the field the editor sees (`hero_image`/`image`), with nothing
  #   assigned, so the record is unchanged. The permission check comes
  #   first, so an actor without `media.upload` doesn't learn which ids
  #   exist.
  #
  # The service's own transaction then saves the reference and refreshes
  # the owner's `media_usages` (`Media::UsageIndex.refresh`). A delete
  # racing this between the existence check and the save still can't
  # leave a dangling reference: the FK refuses the save.
  module Choosing
    private

    # Returns a Result to answer with (a denial or a validation failure),
    # or nil to carry on.
    def media_choice_result(record, attribute, error_attribute)
      return unless @attributes.key?(attribute)

      raw = @attributes[attribute]
      return if raw.blank?

      id = Integer(raw.to_s, 10, exception: false)
      return if id && id == record.public_send(attribute)
      return denied("media.upload", record) unless authorize!("media.upload", record)
      return if id && Media::Asset.exists?(id)

      record.errors.add(error_attribute, "doesn't exist")
      failure(record)
    end
  end
end
