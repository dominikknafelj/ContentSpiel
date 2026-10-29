module Blocks
  # The Table block on the public site (`BlockTypes::Table`, table block
  # spec, "The public side"). Built like `Blocks::NoteComponent`: it reads the
  # block it is handed (a published view on the site, the rows in a preview)
  # and nothing else.
  #
  # Its template is promised seven names and no other (`theme_methods`):
  # `block`, `page`, `rows`, `header_row?`, `header_column?`, `column_count`,
  # `caption`. The scroll box's label ("Table", for a table with no caption to
  # name it) is read in the template from `public.blocks.table.label`, not
  # promised: a method only the default template needs stays in the template.
  #
  # A TABLE WITH NO TEXT DRAWS NOTHING: no cell has text in the visitor's
  # language and none along the site's fallback.
  class TableComponent < ApplicationComponent
    # What the template is handed for a cell: `TableBody::Cell` is the
    # editor's value (its JSON nodes) and stays as it is; this answers the
    # three things a template draws, `html` already scrubbed and safe.
    Cell = Data.define(:header, :align, :html) do
      def header? = header
    end

    def initialize(block:, page:)
      @block = block
      @page = page
    end

    def render? = !table.blank?

    private

    attr_reader :block, :page

    # The body in the visitor's language, else the site's fallback's: the
    # first language that has a table with text (`Locales.read`), the same
    # rule a post's body follows.
    def document = @document ||= ::Locales.read(block, :body)
    def table = @table ||= TableBody.new(document)

    # Each cell's HTML comes from one render of the whole table, cached by
    # the document's digest as a body's render is
    # (`RichText::Document#table_cells_html`), in the context a body's own
    # render has (the visitor's language, the public addresses a cell's link
    # may need), so a cell is drawn as the same text would be in prose. The
    # list is in `table.rows`' order, read from the same document, so a cell
    # takes its HTML by position.
    def rows
      @rows ||= begin
        html = document.table_cells_html(locale: I18n.locale, urls: helpers.public_urls)
        table.rows.each_with_index.map do |row, r|
          row.each_with_index.map { |cell, c| Cell.new(cell.header, cell.align, html.dig(r, c) || "".html_safe) }
        end
      end
    end

    def header_row? = table.header_row?
    def header_column? = table.header_column?
    def column_count = table.column_count

    # The caption in the visitor's language, else the default's; nil for none.
    def caption = translated(block, :caption).to_s.strip.presence
  end
end
