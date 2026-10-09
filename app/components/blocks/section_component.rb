module Blocks
  # A section (`BlockTypes::Section`, sections spec §5): a plain grouping
  # element -- a `<section>` with no accessible name, so not a landmark, and no
  # heading the content doesn't have -- holding a grid with one column per
  # column of its layout. Each column renders its blocks in order with the
  # components that render them at the top level (`ThemeHelper#render_block`,
  # which is also what swaps a listing for a post's detail), so the document
  # reads column 1's blocks, then column 2's: the order they stack in on a
  # narrow screen. The grid, the band and the breakpoints are CSS only
  # (`app/assets/tailwind/themes/default/sections.css`).
  class SectionComponent < ApplicationComponent
    # The width, in CSS pixels, of the public layout's content column: its
    # `max-w-3xl` (768px) less the `px-4` on either side
    # (`app/views/layouts/application.html.erb`).
    CONTENT_WIDTH = 736

    # The `sizes` of an image in `column` of `section` (sections spec §5.4):
    # the column's share of the 736px content column from 768px of viewport
    # up, its share of the viewport while the columns still sit side by side
    # (from 480px, where `sections.css` unstacks them), and the full width
    # below. A hint for the browser's choice among the `srcset` candidates,
    # not a layout: close is enough, too large only costs bytes. So the gap
    # between the columns and a band's own padding are left out (both make
    # the picture a little smaller than asked for), and so is the one place
    # the hint is too small: four columns sit two by two below 44rem of
    # section, where a quarter is asked for and a half is drawn -- the
    # `srcset`'s smallest candidate is wider than either on such a screen.
    def self.image_sizes(section, column)
      weights = BlockTypes::Section.weights(section.settings["layout"])
      share = weights.fetch(column - 1, weights.first).fdiv(weights.sum)
      "(min-width: 768px) #{(CONTENT_WIDTH * share).round}px, (min-width: 480px) #{(share * 100).round}vw, 100vw"
    end

    def initialize(block:, page:)
      @block = block
      @page = page
    end

    # A section with no block renders nothing (sections spec §5.5): an empty
    # band would be a stripe of background with nothing in it. An empty
    # COLUMN keeps its place, so a two-column band with one text stays a
    # half-width text. A block whose type is no longer registered is drawn as
    # nothing (`ThemeHelper#render_block`), so it doesn't count as one.
    def render? = columns.any? { |blocks| blocks.any?(&:definition) }

    # The page's one outline (`ThemeHelper#block_outline`), not one built
    # here: a page of ten sections would otherwise sort and group all its
    # blocks ten times over.
    def columns = @columns ||= helpers.block_outline(page).columns(block)

    # The three settings as the class names they become. Each is read
    # against its own list, so a stored value this code no longer knows --
    # or one written around the service -- reads as the default and never
    # reaches the class attribute.
    def layout = BlockTypes::Section::LAYOUTS.key?(settings.layout.to_s) ? settings.layout : "two"

    def background = BlockTypes::Section::BACKGROUNDS.include?(settings.background.to_s) ? settings.background : "none"

    def width = BlockTypes::Section::WIDTHS.include?(settings.width.to_s) ? settings.width : "content"

    private

    attr_reader :block, :page

    def settings = @settings ||= block.settings_object
  end
end
