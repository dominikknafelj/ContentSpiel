module Blocks
  # A section (`BlockTypes::Section`): a plain grouping
  # element -- a `<section>` with no accessible name, so not a landmark, and no
  # heading the content doesn't have -- holding a grid with one column per
  # column of its layout. Each column renders its blocks in order with the
  # components that render them at the top level (`ThemeHelper#render_block`,
  # which is also what swaps a listing for a post's detail), so the document
  # reads column 1's blocks, then column 2's: the order they stack in on a
  # narrow screen. The grid, the band and the breakpoints are CSS only
  # (`app/assets/tailwind/themes/default/sections.css`).
  class SectionComponent < ApplicationComponent
    include Blocks::Contract

    contract(
      accessibility: "A section with no name of its own, so not a landmark, whose anchor is its id; its columns read in order, as they stack on a narrow screen, and it takes no focus.",
      motion: :none,
      content_edges: %i[none many],
      widths: :from_container,
      interface: %i[block page columns layout background width style anchor],
      words: [],
      limits: [
        "Its full width reaches the window's edges; at the content width it is as wide as what holds it.",
        "A style or a layout it does not know is drawn as none or as two columns, and a section in which nothing draws renders nothing."
      ]
    )

    # The width, in CSS pixels, of the public layout's content column: its
    # `max-w-3xl` (768px) less the `px-4` on either side
    # (`app/views/layouts/application.html.erb`).
    CONTENT_WIDTH = 736

    # The `sizes` of an image in `column` of `section`:
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

    # A section draws nothing when none of its blocks draws anything: an empty
    # band would be a stripe of background with nothing in it. A section
    # with no block, a block whose type is not registered (drawn as
    # nothing by `ThemeHelper#render_block`), and a block that is empty (a
    # Code block with no code) are all no content. The blocks are asked in
    # reading order and the first that draws something ends the question,
    # so a band with content draws its first block twice and an empty one
    # draws nothing. An empty COLUMN keeps its place, so a two-column band
    # with one text stays a half-width text.
    def render?
      columns.any? { |blocks| blocks.any? { |inner| inner.definition && render_block(inner).to_s.strip.present? } }
    end

    # The page's one outline (`ThemeHelper#block_outline`), not one built
    # here: a page of ten sections would otherwise sort and group all its
    # blocks ten times over.
    def columns = @columns ||= helpers.block_outline(page).columns(block)

    # The three settings as the class names they become. Each is read
    # against its own list, so a stored value this code does not know --
    # or one written around the service -- reads as the default and never
    # reaches the class attribute.
    def layout = BlockTypes::Section::LAYOUTS.key?(settings.layout.to_s) ? settings.layout : "two"

    def background = BlockTypes::Section::BACKGROUNDS.include?(settings.background.to_s) ? settings.background : "none"

    def width = BlockTypes::Section::WIDTHS.include?(settings.width.to_s) ? settings.width : "content"

    # The section's style: the stored name when the theme declares it, else
    # nil. A name the theme does not know (another theme's, say) is drawn as
    # no style and left as stored; nothing here writes it. The name is a
    # `Theme::Declarations` name (lowercase letters, digits, underscores), so
    # it is safe as a class suffix.
    def style
      name = settings.style.to_s.strip
      name if name.present? && Theme.current.choice(:section_styles, name)
    end

    # The section's anchor, the section element's `id`: the stored one when it
    # has the shape the service enforces (`BlockTypes::Section::ANCHOR`), else
    # nil, so a value written around the service never reaches an `id`.
    def anchor
      name = settings.anchor.to_s
      name if BlockTypes::Section::ANCHOR.match?(name)
    end

    private

    attr_reader :block, :page

    def settings = @settings ||= block.settings_object
  end
end
