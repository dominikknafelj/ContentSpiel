module Blocks
  # The Gallery block on the public site (`BlockTypes::Gallery`, gallery
  # block spec §7 and §8). It reads the block it is handed -- a published
  # view on the site, the rows in a preview -- and the library images its
  # list names, in one lookup. A theme may replace its template and call only
  # what the type's `theme_methods` names: `layout`, `ratio`, `fit`, `label`,
  # `items`, `sizes`, `string` and `pattern`.
  #
  # AN IMAGE THAT IS GONE IS SKIPPED. The list holds ids; an id that names no
  # image, an image in the trash (both written around the services: a live
  # gallery's usage rows keep its images from the trash) or an image whose
  # file is gone is not an item, and every position ("2 of 5", a slide's name, a dot) counts
  # the items, never the ids. A gallery with no item draws nothing.
  #
  # THE TEXTS ARE TEXT. The label, a caption and an alt reach the page only
  # through ERB's escaping and the picture component's attributes; nothing
  # here marks a string safe.
  #
  # WHAT ONLY THE SCRIPT MAKES WORK (`gallery-carousel`: Previous and Next,
  # the position, the picker and the status) is `hidden` in the template's
  # markup, so without the script a carousel is its track alone, a
  # scroll-snap row that a person scrolls, swipes or moves with the arrow
  # keys on the focused track.
  class GalleryComponent < ApplicationComponent
    include Blocks::FixedWords
    include Blocks::Contract

    contract(
      accessibility: "A grid is a list named by the gallery's label, each image a figure with its alt and caption. " \
                     "A carousel of two or more is a section with the roledescription carousel, named by the label; " \
                     "its track takes the focus and is named Images, each slide is a group with the roledescription slide named \"2 of 5\", " \
                     "and Previous, Next, the position, the picker and a polite status are hidden until gallery-carousel shows them. " \
                     "A carousel of one image is that figure alone.",
      motion: :reduced,
      content_edges: %i[short long missing many],
      widths: :from_container,
      interface: %i[block page layout ratio fit label items sizes string pattern],
      words: %w[public.blocks.gallery.label public.blocks.gallery.carousel public.blocks.gallery.slide
                public.blocks.gallery.position public.blocks.gallery.track public.blocks.gallery.previous
                public.blocks.gallery.next public.blocks.gallery.show public.blocks.gallery.moved],
      limits: [
        "It holds at most 60 images, and the carousel draws a picker of dots for twelve or fewer; above that the position and the buttons alone.",
        "It has no enlarged view, never moves by itself and never wraps from the last image to the first.",
        "An id that names no image, an image in the trash or an image whose file is gone is skipped; " \
        "a gallery with no image that can be drawn renders nothing."
      ]
    )

    # The default theme's grid by the block's own width (`gallery.css`, a
    # size container): one image a row below 360px, two from 360px, three
    # from 640px. What `sizes` divides a width by for that grid.
    GRID_COLUMNS = { 0 => 1, 360 => 2, 640 => 3 }.freeze

    # The default grid's gap in pixels, `--th-gallery-gap` (`--th-sp-3`).
    GRID_GAP = 14

    # The block's public words, the keys of `public.blocks.gallery`: what
    # `string` answers, and nothing else.
    STRINGS = %i[label carousel slide position track previous next show moved].freeze

    # The two sentences the script fills in itself (`%{index}`, `%{count}`):
    # what `pattern` answers, and nothing else.
    PATTERNS = %i[position moved].freeze

    # One image as a template draws it: `index` its 1-based place among the
    # images drawn, `picture` the keywords of `Media::PictureComponent`
    # (`asset`, `alt`, `sizes`), `caption` the caption in the language shown
    # with the site's fallback, or nil.
    Item = Data.define(:index, :picture, :caption)

    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def render? = items.any?

    private

    attr_reader :block, :page

    def settings = @settings ||= block.settings_object(fallback: true)

    # "grid" or "carousel": a stored value this code does not know reads as
    # the default, so it never reaches a class name.
    def layout = BlockTypes::Gallery.layout_of(settings&.layout)

    # The stored ratio ("3:2", "4:3", "1:1", "16:9"), the default for any
    # other value. A template builds its class from it.
    def ratio
      stored = settings&.ratio.to_s
      BlockTypes::Gallery::RATIOS.key?(stored) ? stored : BlockTypes::Gallery::DEFAULT_RATIO
    end

    def fit = settings&.fit == true

    # The gallery's name for a screen reader: its label in the language
    # shown, with the site's fallback, else the visitor's word.
    def label = settings&.label.to_s.strip.presence || string(:label)

    # The images that can be drawn, in the gallery's order (`Item`).
    #
    # The ALT is the gallery's override in the language shown, else the
    # library image's, interleaved per language (`Media::Asset#alt_text`
    # handed the overrides as `{ locale => alt }`), so an English override
    # never beats the library's own German alt on a German page. The
    # CAPTION has no library default (spec §8): it is the gallery's own,
    # the first written along the site's fallback chain, image by image.
    def items
      @items ||= begin
        ids = Array(settings&.images)
        found = ids.empty? ? {} : Media::Asset.kept.with_file.where(id: ids).index_by(&:id)
        drawn = ids.filter_map { |id| found[id] }.select { |asset| asset.file.attached? }
        texts = block.translated_settings.to_h.transform_values { |values| values.to_h["texts"].to_h }
        chain = Locales.fallback_chain(I18n.locale)
        image_sizes = sizes(per_row: layout == "grid" ? GRID_COLUMNS : 1)

        drawn.each_with_index.map do |asset, position|
          own = texts.transform_values { |by_id| by_id[asset.id.to_s].to_h }
          alt = asset.alt_text(override: own.transform_values { |values| values["alt"] }.compact)
          caption = chain.lazy.filter_map { |code| own.dig(code, "caption").to_s.strip.presence }.first
          Item.new(index: position + 1, picture: { asset: asset, alt: alt, sizes: image_sizes }.freeze, caption: caption)
        end.freeze
      end
    end

    # The `sizes` of one image when a row holds `per_row` of them (spec
    # §7.1): each width `Blocks::ImageComponent.sizes_for(block)` names,
    # divided by the count for it. `per_row` is an Integer, or a Hash of the
    # block's least width in pixels to the count a row holds from there.
    #
    # A width in pixels is the block's own (the content column, which is
    # `SectionComponent::CONTENT_WIDTH` and not the 768px the image's hint
    # asks, or a section column's share of it), so it takes the count of its
    # width and asks `round((W - (n - 1) * gap) / n)`. A width relative to
    # the viewport can be any block's, a phone's one column among them, so
    # it takes the narrowest block's count, `per_row`'s least key, and is
    # divided without the gaps: it asks more than a row draws, never less. A
    # count of one leaves the width as `sizes_for` names it.
    def sizes(per_row: 1)
      counts = per_row.is_a?(Hash) ? per_row.sort.to_h : { 0 => per_row }
      Blocks::ImageComponent.sizes_for(block).split(", ").map do |entry|
        condition, _, width = entry.rpartition(" ")
        [ condition.presence, share_of(width, counts) ].compact.join(" ")
      end.join(", ")
    end

    def share_of(width, counts)
      number = width.to_i
      if width.end_with?("px")
        wide = [ number, Blocks::SectionComponent::CONTENT_WIDTH ].min
        count = counts.select { |least, _| least <= wide }.values.last || counts.values.first
        count == 1 ? width : "#{(wide - (count - 1) * GRID_GAP).fdiv(count).round}px"
      else
        count = counts.values.first
        count == 1 ? width : "#{number.fdiv(count).ceil}vw"
      end
    end

    # One of the block's public words, in the visitor's language where
    # `config/locales/public.<locale>.yml` has it, in English otherwise;
    # `values` fill its `%{…}` and none may be left out. Another key is
    # refused (`Blocks::FixedWords`).
    def string(key, **values) = fixed_word(key, scope: "public.blocks.gallery", owner: "the Gallery block's", **values)

    # A sentence the script fills in itself, `position` or `moved`, with its
    # `%{index}` and `%{count}` left in: what a template writes into the
    # script's two values.
    def pattern(key)
      unless PATTERNS.include?(key.to_s.to_sym)
        return refused_word(key, "#{self.class.name}#pattern has no #{key.to_s.to_sym.inspect}: the Gallery block's patterns are #{PATTERNS.map(&:inspect).join(", ")}")
      end

      fixed_word(key, scope: "public.blocks.gallery", owner: "the Gallery block's")
    end
  end
end
