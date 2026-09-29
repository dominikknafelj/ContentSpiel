module Blocks
  # A single library image with a caption and alt text (`BlockTypes::Image`).
  # The image is the block's `media_asset` (media library design spec §3.3);
  # the block's own translated `alt`/`caption` override the asset's defaults
  # locale by locale (`Media::Asset#alt_text`/`#caption_text`). Rendered through
  # `Media::PictureComponent` (media library Task 5) for a real `srcset`.
  class ImageComponent < ApplicationComponent
    # The one `sizes` value this app picks for a content-width image
    # (design spec §4: "pick one and comment it"). The public layout's own
    # content column tops out at `max-w-3xl` (768px,
    # `app/views/layouts/application.html.erb`) with no further inset once
    # the viewport reaches it, so a block image (and, per
    # `RichText::ImageComponent`, a rich-text one) is exactly that column's
    # width from 768px up, and the full viewport width below it -- unlike
    # the page hero (`app/views/pages/show.html.erb`, `sizes: "100vw"`),
    # which always spans the viewport regardless of the content column.
    SIZES = "(min-width: 768px) 768px, 100vw"

    def initialize(block:, page:)
      @block = block
      @page = page
    end

    private

    attr_reader :block, :page

    def asset = block.media_asset

    # The block's overrides go in whole, as their `{locale => value}` jsonb
    # (final fix wave, I1): `Media::Asset#alt_text` interleaves them with the
    # asset's own defaults per locale, so an override written in another
    # language never beats the asset's default in this one -- which
    # resolving them first through `translated` (the fallback chain) did.
    def alt = asset.alt_text(override: block.read_attribute(:alt))

    def caption = asset.caption_text(override: block.read_attribute(:caption))
  end
end
