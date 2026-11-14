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
        t.field :source, :mermaid, translated: true, max: Diagrams::Source::MAX_CHARACTERS, drawing: :drawing
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
        t.sample settings: {},
                 translations: {
                   "en" => { source: SAMPLE_SOURCES["en"], drawing: -> { sample_drawing("en") },
                             description: "A flowchart: a draft goes to review, and is published once approved or sent back to the draft with changes.",
                             caption: "How a page is published" },
                   "de" => { source: SAMPLE_SOURCES["de"], drawing: -> { sample_drawing("de") },
                             description: "Ein Flussdiagramm: Ein Entwurf geht zur Prüfung und wird nach der Freigabe veröffentlicht oder mit Änderungen an den Entwurf zurückgegeben.",
                             caption: "Wie eine Seite veröffentlicht wird" },
                   "es" => { source: SAMPLE_SOURCES["es"], drawing: -> { sample_drawing("es") },
                             description: "Un diagrama de flujo: un borrador pasa a revisión y se publica cuando se aprueba o vuelve al borrador con cambios.",
                             caption: "Cómo se publica una página" }
                 },
                 shows: [ "A flowchart: a draft goes to review, and is published once approved or sent back to the draft with changes.", "How a page is published" ]
      end
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
