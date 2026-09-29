module Admin
  module Columns
    # A file input plus the current image (spec §4.3), for a page's hero
    # and an image block's image -- both library `Media::Asset`s since media
    # library Task 4, uploaded through `Media::Upload` (`Admin::FileParams
    # #upload_to_library`) until Task 8's picker replaces this field --
    # and, unrelated to the library, `SiteSetting#logo`. `value` is the
    # asset's `file` attachment (an `ActiveStorage::Attached::One`) or nil,
    # not a URL -- `attached?` and `helpers.image_tag` both work directly
    # off it.
    class ImageColumnComponent < Base
      def attached? = value.respond_to?(:attached?) && value.attached?

      # The thumbnail actually shown: the `w480` variant (media library
      # global constraints) when `value`'s owning record is a library
      # `Media::Asset` with one ready, else the original file -- exactly
      # "the w480 variant or the original" (Task 5 brief). This goes through
      # `Media::Asset#srcset` rather than `value.variant(:w480)` directly,
      # for two reasons: `#srcset` already skips a GIF (no variants at all,
      # global constraints) and anything not yet processed, so this thumbnail
      # can never trigger a synchronous transform or request a variant that
      # doesn't exist for this asset's content type; and `value` isn't
      # always a `Media::Asset`'s file at all -- `SiteSetting#logo` reaches
      # this same component with no `w480` named variant registered on its
      # own attachment, which `value.variant(:w480)` would raise
      # `ArgumentError` against (`ActiveStorage::Attachment
      # #transformations_by_name`) rather than quietly fall back. Checking
      # `value.record.is_a?(Media::Asset)` first is what keeps the logo (and
      # any other future non-library attachment this component might be
      # asked to show) on its own original-only path instead.
      def thumbnail_source
        return value unless attached?

        asset = value.record
        return value unless asset.is_a?(Media::Asset)

        w480_url, = asset.srcset.find { |_url, width| width == Media::Asset::VARIANT_WIDTHS[:w480] }
        w480_url || asset.url
      end
    end
  end
end
