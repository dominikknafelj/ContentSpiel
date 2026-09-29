module Admin
  module Columns
    # A file input plus the current image (spec §4.3), for a page's hero
    # and an image block's image -- both library `Media::Asset`s since media
    # library Task 4, uploaded through `Media::Upload` (`Admin::FileParams
    # #upload_to_library`) until Task 8's picker replaces this field.
    # `value` is the asset's `file` attachment (an `ActiveStorage::Attached
    # ::One`) or nil, not a URL -- `attached?` and `helpers.image_tag` both
    # work directly off it.
    class ImageColumnComponent < Base
      def attached? = value.respond_to?(:attached?) && value.attached?
    end
  end
end
