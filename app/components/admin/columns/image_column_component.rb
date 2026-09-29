module Admin
  module Columns
    # A file input plus the current image (spec §4.3) -- today only for
    # `SiteSetting#logo`, which stays an attachment of its own rather than
    # a library image (media library global constraints). A page's hero and
    # an image block's image used this until media library Task 8; they're
    # library `Media::Asset`s chosen through the picker now
    # (`Admin::Columns::MediaColumnComponent`). `value` is the attachment
    # (an `ActiveStorage::Attached::One`) or nil, not a URL -- `attached?`
    # and `helpers.image_tag` both work directly off it, and the thumbnail
    # is the original file: the logo has no named variants to pick from.
    class ImageColumnComponent < Base
      def attached? = value.respond_to?(:attached?) && value.attached?

      def thumbnail_source = value
    end
  end
end
