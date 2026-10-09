module Blocks
  # A section (`BlockTypes::Section`): a plain grouping element holding one
  # column per column of its layout, each rendering its blocks in order with
  # the components that render them at the top level (`ThemeHelper
  # #render_block`, which is also what swaps a listing for a post's detail).
  class SectionComponent < ApplicationComponent
    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def columns = BlockOutline.new(page.content_blocks).columns(block)

    private

    attr_reader :block, :page
  end
end
