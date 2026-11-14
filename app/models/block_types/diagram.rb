module BlockTypes
  # A diagram written as Mermaid text, drawn in CS Studio and shown on the
  # site as a cleaned SVG (Diagram block spec §1). All four values are
  # translated, so each language may have a diagram of its own:
  #
  # - `source`, the Mermaid text, in `translated_settings` (`:mermaid`, never
  #   offered to an AI provider);
  # - `drawing`, the cleaned SVG and the digest of the source it was drawn
  #   from, beside it (`:diagram_drawing`, written by the editor's script,
  #   cleaned again by its cast and untracked for translation state, since it
  #   follows the source);
  # - `description`, the words for people who can't see the diagram, which
  #   the site needs before it shows the diagram at all, so a language
  #   without one is missing a translation (`translation_required:`);
  # - the caption, the block's existing `caption` column.
  #
  # Nothing is required for a save: the block picker makes an empty block
  # first, and the public component draws nothing until a language has a
  # drawing and a description. The line rules and the limits are
  # `Diagrams::Source`'s, the reading of a drawing `Diagrams::Drawing`'s.
  module Diagram
    # The sample's source in each language: one flowchart, its labels in the
    # language. `test/fixtures/diagrams/sources.yml` holds the same three
    # (`sample_<locale>`), from which `bin/rails diagram:fixtures` writes the
    # drawings in `SAMPLE_DRAWINGS`; `test/models/block_types/diagram_test.rb`
    # holds each drawing current for its source here.
    SAMPLE_SOURCES = {
      "en" => <<~MERMAID,
        flowchart LR
          accDescr: A draft goes to review, and is published once approved or sent back with changes.
          A[Draft] --> B{Review}
          B -->|approved| C[Published]
          B -->|changes| A
      MERMAID
      "de" => <<~MERMAID,
        flowchart LR
          accDescr: Ein Entwurf geht zur Prüfung und wird nach der Freigabe veröffentlicht oder mit Änderungen zurückgeschickt.
          A[Entwurf] --> B{Prüfung}
          B -->|freigegeben| C[Veröffentlicht]
          B -->|Änderungen| A
      MERMAID
      "es" => <<~MERMAID
        flowchart LR
          accDescr: Un borrador pasa a revisión y se publica cuando se aprueba o se devuelve con cambios.
          A[Borrador] --> B{Revisión}
          B -->|aprobado| C[Publicado]
          B -->|cambios| A
      MERMAID
    }.freeze

    # The sample's drawings, already cleaned, in `db/seeds/` and not `test/`:
    # the sample is registered in every environment and the development
    # showcase draws it. They are read when the sample is first asked for,
    # never while the type registers.
    SAMPLE_DRAWINGS = Rails.root.join("db/seeds/diagrams")

    def self.register
      BlockTypes.register :diagram do |t|
        t.label "Diagram"
        t.icon "diagram", family: :code
        t.field :source, :mermaid, translated: true, max: Diagrams::Source::MAX_CHARACTERS, drawing: :drawing, description: :description
        t.field :drawing, :diagram_drawing, translated: true
        t.field :description, :text, translated: true, translation_required: true, label: "Description",
                help: "Describe what the diagram shows, for people who can't see it. The diagram shows on the site only with a description."
        t.uses :caption
        t.component Blocks::DiagramComponent
        # `svg` is the cleaned drawing's markup, named by the description;
        # `description` and `caption` are the block's words in the visitor's
        # language.
        t.theme_methods :block, :page, :svg, :description, :caption
        # What diagram.css paints a drawing with, by Mermaid's class names:
        # from the theme's base tokens in tokens.css but the six series
        # colours (a pie's slices, a gantt's task states), which are literals
        # as the syntax colours are; re-valued by a strong band in
        # sections.css. The font is fixed: Mermaid measured every box in it.
        t.tokens themed: %w[diagram-ink diagram-fill diagram-line diagram-edge diagram-group diagram-note diagram-accent
                            diagram-series-1 diagram-series-2 diagram-series-3 diagram-series-4 diagram-series-5 diagram-series-6],
                 fixed: %w[diagram-font]
        t.stylesheet "diagram.css"
        t.summary ->(block, locale:) { Diagram.summary(block, locale: locale) }
        t.preview ->(block, locale:) { Diagram.preview(block, locale: locale) }
        t.tile_picture ->(block, locale:) { Diagram.tile_picture(block, locale: locale) }
        t.sample settings: {},
                 translations: {
                   "en" => { source: SAMPLE_SOURCES["en"], drawing: -> { sample_drawing("en") },
                             description: "A flowchart: a draft goes to review, then is published or sent back.",
                             caption: "How a page is published" },
                   "de" => { source: SAMPLE_SOURCES["de"], drawing: -> { sample_drawing("de") },
                             description: "Ein Flussdiagramm: Ein Entwurf wird geprüft, dann veröffentlicht oder zurückgegeben.",
                             caption: "Wie eine Seite veröffentlicht wird" },
                   "es" => { source: SAMPLE_SOURCES["es"], drawing: -> { sample_drawing("es") },
                             description: "Un diagrama de flujo: un borrador pasa a revisión y se publica o se devuelve.",
                             caption: "Cómo se publica una página" }
                 },
                 shows: [ "A flowchart: a draft goes to review, then is published or sent back.", "How a page is published" ]
      end
    end

    SUMMARY_LENGTH = ContentModel::BlockTypeDefinition::SUMMARY_LENGTH

    # block object => { [locale, stored values] => Shown }, held no longer
    # than the block object is.
    MEMO = ObjectSpace::WeakMap.new

    # What a closed block's tile reads in a language, by the public
    # component's fallback (`Blocks::DiagramComponent`): the source and the
    # drawing of the first language on the fallback chain with a source of
    # its own, and the description of the language itself, or else of the
    # language whose drawing it is. Read as stored, the drawing not cast.
    #
    # One tile asks it three times (its line, its preview and its picture),
    # so it is kept per block object, language and stored values
    # (`MEMO`): the three share one `Diagrams::Drawing`, which parses its
    # drawing once and keeps its markup. A save hands the tile a block whose
    # stored values changed, and so reads them again.
    Shown = Data.define(:source, :drawing, :description) do
      def self.for(block, locale:)
        stored = block.translated_settings.to_h
        kept = (MEMO[block] ||= {})
        key = [ locale.to_s, stored ]
        return kept[key] if kept.key?(key)

        kept.clear
        kept[key] = read(block, stored, locale)
      end

      def self.read(block, stored, locale)
        code = ::Locales.fallback_chain(locale).map(&:to_s).find { |candidate| stored.dig(candidate, "source").present? }
        return unless code

        drawing = stored.dig(code, "drawing")
        drawing = nil unless drawing.is_a?(Hash) && drawing["svg"].is_a?(String) && drawing["svg"].present?
        description = [ locale.to_s, code ].uniq.lazy.filter_map { |candidate| stored.dig(candidate, "description").presence }.first
        new(source: stored.dig(code, "source"), drawing: drawing && Diagrams::Drawing.new(drawing), description: description)
      end
      private_class_method :read

      # The stored drawing when it passes on read: what the site shows.
      def shown_drawing = (drawing if drawing&.reason.nil?)
    end

    # The tile's line, as parts (Diagram block spec, the tile): the type's
    # label, " · " and the source's first line after the keyword in the
    # monospace face, or the source's first line alone when its keyword is
    # none of the block's; then each hint in the meta colour, never danger:
    # no description, a drawing kept from an earlier source (the site shows
    # it, so the tile does too, undimmed), or no drawing the site could show.
    # With no source in the language or its fallback it says Empty.
    def self.summary(block, locale:)
      shown = Shown.for(block, locale: locale)
      return [ [ :hint, :empty ] ] unless shown

      label = Diagrams::Source::TYPES[Diagrams::Source.type(shown.source)]
      first = label ? Diagrams::Source.first_line(shown.source) : shown.source.lines.map(&:strip).find(&:present?)
      line = [ ([ :text, label ] if label), ([ :text, " · " ] if label && first), ([ :mono, first.truncate(SUMMARY_LENGTH) ] if first) ].compact
      line + hints(shown).flat_map { |hint| [ [ :text, " · " ], [ :hint, hint ] ] }
    end

    def self.hints(shown)
      drawing = shown.shown_drawing
      [
        (:no_description if shown.description.blank?),
        (:kept if drawing && !drawing.current?(shown.source)),
        (:not_drawn unless drawing)
      ].compact
    end
    private_class_method :hints

    # The tile's words: the description's opening words over the source's
    # first three lines in the monospace face. Nil with no source.
    def self.preview(block, locale:)
      shown = Shown.for(block, locale: locale)
      return unless shown

      ContentModel::Preview.new(heading: shown.description, text: shown.source.lines.first(3).join, mono: true)
    end

    # The tile's small picture: the drawing the site would show, named by the
    # description, its ids the tile's own (`diagram-tile-<block>-<locale>-`,
    # never the card's frame's or the page's), in an element of the public
    # block's class, so CS Studio's stylesheet paints it with the block's
    # own rules on CS Studio's colours. Hidden from a screen reader: the
    # line beside it names the block. Nil when there is no drawing that
    # passes on read.
    def self.tile_picture(block, locale:)
      shown = Shown.for(block, locale: locale)
      drawing = shown&.shown_drawing
      return unless drawing

      prefix = "diagram-tile-#{block.id}-#{locale}-"
      svg = drawing.markup(prefix: prefix, title: shown.description.to_s, title_id: "#{prefix}title")
      svg && ActiveSupport::SafeBuffer.new.safe_concat(%(<span class="content-block--diagram" aria-hidden="true">)).concat(svg).safe_concat("</span>")
    end

    # The sample's drawing in a language: the cleaned SVG `diagram:fixtures`
    # wrote and, as its `from`, the digest of the source it was drawn from,
    # which the task wrote beside it. A source changed without drawing it
    # again leaves the drawing not current for it.
    def self.sample_drawing(locale)
      { "svg" => SAMPLE_DRAWINGS.join("sample-#{locale}.svg").read, "from" => SAMPLE_DRAWINGS.join("sample-#{locale}.from").read.strip }
    end
  end
end
