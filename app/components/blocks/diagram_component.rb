module Blocks
  # The Diagram block on the public site: a figure holding the drawing,
  # named by the block's description, over its caption (Diagram block spec
  # §6). A theme may replace its template and call only what the type's
  # `theme_methods` names.
  #
  # THE SOURCE AND THE DRAWING FALL BACK TOGETHER. The drawing shown is that
  # of the first language on the visitor's fallback chain that has a source
  # of its own: a language with its own source shows only its own drawing
  # (none, if it has none or it fails on read), never another language's
  # beside its source. The description names that drawing: the visitor's
  # language's own, or else that of the language whose drawing is shown,
  # and none from further down the chain, which would name another drawing.
  # The caption falls back on its own, as every translated text does.
  #
  # THE READ IS CACHED BY ITS CONTENT (`.cache_key`): the stored drawing's
  # digest, the block, the visitor's language (the ids' prefix) and
  # `Diagrams::Drawing::REVISION` (the sanitizer's rules and what its markup
  # writes). The entry is the drawing's markup without its title, or why it
  # fails on read, so a page read again parses nothing: the stored drawing is
  # read as stored from `translated_settings`, never through the `:diagram_drawing`
  # cast, which cleans it again. The title is the description, which changes
  # on its own, and is written into the cached markup on every read. This is
  # a value the component computes, not a fragment of the page: what it
  # prints is a function of the block alone, as the page's ETag sees it, so
  # it is right for every visitor and for a preview too.
  #
  # A drawing that fails on read is logged once per entry: the entry is the
  # mark that it was, and holds the reason, never the drawing.
  class DiagramComponent < ApplicationComponent
    include Blocks::Contract

    contract(
      accessibility: "A figure whose svg is an image (role img) named by the block's description in a title of its own, and described by Mermaid's accDescr when the drawing keeps one; the caption is a figcaption.",
      motion: :none,
      content_edges: %i[short long missing],
      widths: :from_container,
      interface: %i[block page svg description caption],
      words: [],
      limits: [
        "Nothing is drawn without a drawing that passes on read or without a description: there is no error text and no empty box.",
        "The drawing keeps the width and height of its viewBox and scales down to its column to three fifths of that; narrower, it scrolls sideways in its own box, never the page.",
        "The scroll box is a keyboard stop whether it scrolls or not: the component cannot know the column's width."
      ]
    )

    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def render? = svg.present? && description.present?

    # The cache key of a read: the stored drawing, the block, the language
    # and the sanitizer's revision.
    def self.cache_key(svg, block_id:, locale:) = [ "diagram", Digest::SHA256.hexdigest(svg), block_id, locale.to_s, Diagrams::Drawing::REVISION ]

    private

    attr_reader :block, :page

    # The drawing's markup, its ids prefixed with the block and the visitor's
    # language so two blocks of one drawing on a page share none, and its
    # `<title>` the description; nil with no drawing, none that passes on
    # read, or no description to name it.
    def svg
      return @svg if defined?(@svg)

      stored = stored_svg if description.present?
      untitled = stored && read(stored)["markup"]
      @svg = untitled && Diagrams::Drawing.with_title(untitled, title: description, title_id: "#{prefix}title")
    end

    # The visitor's language's own description, or else that of the language
    # whose drawing is shown.
    def description
      return @description if defined?(@description)

      @description = [ I18n.locale.to_s, drawing_locale ].compact.uniq.lazy.filter_map { |code| block.settings_object(locale: code)&.description.presence }.first
    end

    def caption = translated(block, :caption)

    # The first language on the visitor's fallback chain with a source of
    # its own: the one whose drawing is shown.
    def drawing_locale
      return @drawing_locale if defined?(@drawing_locale)

      @drawing_locale = ::Locales.fallback_chain(I18n.locale).map(&:to_s).find { |code| block.translated_settings.to_h.dig(code, "source").present? }
    end

    def prefix = "diagram-#{block.id}-#{I18n.locale}-"

    # The stored drawing's SVG of that language, as stored: read with no
    # fallback and not cast.
    def stored_svg
      value = drawing_locale && block.translated_settings.to_h.dig(drawing_locale, "drawing")
      value["svg"].presence if value.is_a?(Hash) && value["svg"].is_a?(String)
    end

    # `{ "markup" => untitled markup }` or `{ "reason" => why it fails }`,
    # through the cache.
    def read(stored)
      Rails.cache.fetch(self.class.cache_key(stored, block_id: block.id, locale: I18n.locale)) do
        drawing = Diagrams::Drawing.new("svg" => stored)
        if (markup = drawing.untitled_markup(prefix: prefix, title_id: "#{prefix}title"))
          { "markup" => markup }
        else
          Rails.logger.warn("Blocks::DiagramComponent: the drawing of block #{block.id} (#{drawing_locale}) fails on read (#{drawing.reason}) and is not shown")
          { "reason" => drawing.reason.to_s }
        end
      end
    end
  end
end
