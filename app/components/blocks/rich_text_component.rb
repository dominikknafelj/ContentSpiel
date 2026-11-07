module Blocks
  # Free-form rich text (`BlockTypes::RichText`). Ported verbatim from the old
  # (now deleted) `content_blocks` `_rich_text` partial -- `body` is rendered through `rich_text`
  # (ThemeHelper), which walks `Locales.fallback_chain` for a locale left
  # blank.
  class RichTextComponent < ApplicationComponent
    include Blocks::Contract

    contract(
      accessibility: "A div with no role or name of its own: the headings, lists and links are the rich text's, and nothing but its links takes focus.",
      motion: :none,
      content_edges: %i[long short],
      widths: :from_container,
      interface: %i[block page],
      words: [],
      limits: [
        "Its elements and their classes are the rich-text renderer's (`rich_text`), not the template's.",
        "An empty body renders nothing."
      ]
    )

    def initialize(block:, page:)
      @block = block
      @page = page
    end

    # Nothing to draw when the body is blank in the visitor's language and in
    # every fallback (`Locales.read` walks the chain, as `ThemeHelper#rich_text`
    # does; `Document#blank?` counts a lone empty paragraph as blank): the
    # wrapper would be an empty box, and a section decides whether it has a
    # band by what its blocks draw (`Blocks::SectionComponent#render?`,
    # contrast and buttons spec, Ruling 19). Asked of the document, so the
    # body is not rendered twice.
    def render? = !::Locales.read(block, :body).blank?

    private

    attr_reader :block, :page
  end
end
