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
    # An image in a column of a section is narrower than that, and asks for
    # its column's width instead (`#sizes`).
    SIZES = "(min-width: 768px) 768px, 100vw"

    def initialize(block:, page:)
      @block = block
      @page = page
    end

    # Nothing at all without an image (the template's own condition): a
    # template that draws nothing still leaves ViewComponent's annotation
    # comments in development, which `Blocks::SectionComponent#render?` reads
    # as something drawn and so draws an empty band (Ruling 19). Not drawing
    # the component leaves no markup, comments included.
    def render? = asset&.file&.attached? || false

    private

    attr_reader :block, :page

    def asset = block.media_asset

    # The one thing a block's component knows about where it sits (sections
    # spec §5.4): an image in a column asks for a picture as wide as its
    # column, not as wide as the page. `block.section` is the object the
    # page's outline handed over (`BlockOutline`), so reading it is no query.
    # A section whose type is gone draws no columns -- its blocks are stacked
    # at the content width (`ThemeHelper#render_block`) -- so its images ask
    # for that.
    def sizes
      section = block.section if block.section_id
      section&.container? ? Blocks::SectionComponent.image_sizes(section, block.section_column) : SIZES
    end

    # The block's overrides go in whole, as their `{locale => value}` jsonb
    # (final fix wave, I1): `Media::Asset#alt_text` interleaves them with the
    # asset's own defaults per locale, so an override written in another
    # language never beats the asset's default in this one -- which
    # resolving them first through `translated` (the fallback chain) did.
    # Each answers nil for a block with no image: a theme's template may call
    # them without the default template's guard around them (theming spec §3,
    # `Theme::Contract.components`).
    def alt = asset&.alt_text(override: block.read_attribute(:alt))

    def caption = asset&.caption_text(override: block.read_attribute(:caption))
  end
end
