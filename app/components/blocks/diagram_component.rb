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
  # beside its source. The description and the caption fall back on their
  # own, as every translated text does.
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
        "The drawing is sized from its viewBox and is not yet scaled to its column."
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

    def description = settings&.description

    def caption = translated(block, :caption)

    # The settings in the visitor's language, with the site's fallback.
    def settings = @settings ||= block.settings_object(fallback: true)

    # The stored drawing of the language whose source is shown.
    def drawing_value
      code = ::Locales.fallback_chain(I18n.locale).find { |candidate| block.translated_settings.to_h.dig(candidate.to_s, "source").present? }
      code && block.settings_object(locale: code)&.drawing
    end
  end
end
