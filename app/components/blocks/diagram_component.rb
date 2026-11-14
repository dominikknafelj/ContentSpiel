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
        "The drawing keeps the width and height of its viewBox: nothing scales it to its column."
      ]
    )

    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def render? = svg.present? && description.present?

    private

    attr_reader :block, :page

    # The drawing's markup, its ids prefixed with the block and the visitor's
    # language so two blocks of one drawing on a page share none, and its
    # `<title>` the description; nil with no drawing, none that passes on
    # read, or no description to name it.
    def svg
      return @svg if defined?(@svg)

      prefix = "diagram-#{block.id}-#{I18n.locale}-"
      drawing = drawing_value
      @svg = if drawing && description.present?
        Diagrams::Drawing.new(drawing).markup(prefix: prefix, title: description, title_id: "#{prefix}title")
      end
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

    # The stored drawing of that language, read with no fallback.
    def drawing_value = drawing_locale && block.settings_object(locale: drawing_locale)&.drawing
  end
end
