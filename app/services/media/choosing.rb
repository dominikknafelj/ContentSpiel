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
  # leave a dangling reference: the FK refuses the save. That refusal
  # (`ActiveRecord::InvalidForeignKey`) is rescued by the service and
  # answered by `#vanished_media_failure` (final fix wave, M1) -- the same
  # "doesn't exist" failure as a forged id, never a 500. It also covers the
  # rich-text side, which is why `Posts::Save` includes this module too: an
  # image a body embeds can go between the body's own existence check (or
  # `UsageIndex`'s) and the insert of its `media_usages` row, whose FK
  # then refuses it.
  module Choosing
    private

    # Returns a Result to answer with (a denial or a validation failure),
    # or nil to carry on.
    def media_choice_result(record, attribute, error_attribute)
      return unless @attributes.key?(attribute)

      raw = @attributes[attribute]
      return if raw.blank?

      id = Integer(raw.to_s, 10, exception: false)
      # "Resending the stored id" means the *stored* one (final fix wave,
      # M2): an id someone already assigned in memory isn't stored, and
      # comparing with it would skip the permission check below.
      return if id && id == record.attribute_in_database(attribute)
      return denied("media.upload", record) unless authorize!("media.upload", record)
      return if id && Media::Asset.exists?(id)

      record.errors.add(error_attribute, "doesn't exist")
      failure(record)
    end

    # The failure for a save the FK refused (see the module comment). The
    # transaction has rolled back; the refused reference is still assigned
    # in memory, so it tells the two cases apart: the record's own
    # `reference_attribute` naming an asset that's gone is reported on
    # `error_attribute` (the field the editor sees), anything else was a
    # body's image on its way into `media_usages`. Pass nil for an owner
    # with no reference column of its own (a post). Only a violation of a
    # `media_assets` FK is answered here: any other refused FK (a parent
    # page, tag or author deleted mid-save) re-raises rather than being
    # misreported as a missing image on a field the form may not even show.
    def vanished_media_failure(error, record, reference_attribute, error_attribute)
      raise error unless error.message.include?("media_assets")

      id = reference_attribute && record.public_send(reference_attribute)
      if id && !Media::Asset.exists?(id)
        record.errors.add(error_attribute, "doesn't exist")
      else
        record.errors.add(:body, "has an image that doesn't exist")
      end
      failure(record)
    end
  end
end
