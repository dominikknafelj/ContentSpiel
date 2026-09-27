module Admin
  module Columns
    # A file input plus the current image (spec §4.3), for a
    # `has_one_attached` column (`Page#hero_image`, `ContentBlock#image`).
    # `value` is the attachment itself (an `ActiveStorage::Attached::One`),
    # not a URL -- `attached?` and `helpers.image_tag` both work directly
    # off it, the same way a page/block view already renders one.
    class ImageColumnComponent < Base
      def attached? = value.respond_to?(:attached?) && value.attached?
    end
  end
end
