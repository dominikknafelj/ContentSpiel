module Blocks
  # A single attached image with a caption and alt text (`BlockTypes::Image`).
  # Ported verbatim from the old (now deleted) `content_blocks` `_image` partial.
  class ImageComponent < ApplicationComponent
    def initialize(block:, page:)
      @block = block
      @page = page
    end

    private

    attr_reader :block, :page
  end
end
