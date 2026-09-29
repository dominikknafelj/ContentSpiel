module Blocks
  # A single library image with a caption and alt text (`BlockTypes::Image`).
  # The image is the block's `media_asset` (media library design spec §3.3);
  # the block's own translated `alt`/`caption` override the asset's defaults
  # (`Media::Asset#alt_text`/`#caption_text`). Rendered from the original
  # file for now -- Task 5 swaps in `Media::PictureComponent`.
  class ImageComponent < ApplicationComponent
    def initialize(block:, page:)
      @block = block
      @page = page
    end

    private

    attr_reader :block, :page

    def asset = block.media_asset
  end
end
