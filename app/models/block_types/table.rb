module BlockTypes
  # A table of cells in the flow of a page (table block spec). Its values
  # live where a Note's do and no new column exists: the grid is the block's
  # ordinary `body`, one `table` node per language (`t.body_content :table`
  # says the body holds that and not prose, and `HasRichTextBody` holds the
  # body to the rule), and the caption is the block's `caption` column. So no
  # migration and no service. Nothing is required: the picker makes an empty
  # Table first, and the public component draws nothing until a cell has
  # text.
  module Table
    # The tile's line is cut at the length the tile cuts every line at.
    SUMMARY_LENGTH = ContentModel::BlockTypeDefinition::SUMMARY_LENGTH

    def self.register
      BlockTypes.register :table do |t|
        t.label "Table"
        t.icon "table"
        t.uses :body, :caption
        t.body_content :table
        t.component Blocks::TableComponent
        # `rows` the cells by row (a cell answers `header?`, `align` and
        # `html`, its text rendered and safe); `header_row?` and
        # `header_column?` whether the first row, the first column are
        # headers; `column_count` the widest row; `caption` the caption in
        # the visitor's language, else the default's. The scroll box's label
        # is the template's own key, not a promise.
        t.theme_methods :block, :page, :rows, :header_row?, :header_column?, :column_count, :caption
        t.tokens themed: %w[table-rule table-line table-head table-caption table-ground]
        t.stylesheet "table.css"
        t.summary ->(block, locale:) { Table.summary(block, locale: locale) }
        t.sample translations: { "en" => { caption: "Plans compared" }, "de" => { caption: "Tarife im Vergleich" }, "es" => { caption: "Planes comparados" } },
                 body: <<~MARKDOWN,
                   | Plan | Monthly price | Storage |
                   | --- | ---: | --- |
                   | **Basic** | 5 € | 10 GB |
                   | Pro | 12 € | [Unlimited](https://example.com) |
                 MARKDOWN
                 shows: [ "Plans compared", "Monthly price", "Unlimited" ]
      end
    end

    # The tile's line of a closed Table, as parts: "Table · 3 × 3 · " (columns
    # by rows, of the language shown) and the caption, else the first
    # header words (the first row's text), or "Empty table" in the meta
    # colour (alone) when no cell has text in this language.
    def self.summary(block, locale:)
      body = TableBody.new(block.body_document(locale: locale))
      return [ [ :hint, :empty ] ] if body.blank?

      line = [ :text, "Table · #{body.column_count} × #{body.row_count}" ]
      # The caption, else the words of the first row that has any text (a
      # table whose header row is blank is not a table with no words).
      first = block.caption(locale: locale).to_s.strip.presence ||
              body.rows.map { |row| row.map { |cell| cell.text.strip }.reject(&:empty?).join(" ") }.find(&:present?)
      return [ line ] unless first

      [ [ :text, "#{line.last} · " ], [ :text, first.truncate(SUMMARY_LENGTH) ] ]
    end
  end
end
