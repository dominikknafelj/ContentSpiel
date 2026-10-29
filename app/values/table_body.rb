# A Table block's body read as what it is: rows of cells (table block spec,
# decisions 2, 3 and 5). The body stays a rich-text document, one `table`
# node (`RichText::BuiltIns`), because that is what the editor, the Markdown
# form and the stored copies already speak; this value is how everything else
# (the public template, the editor's summary, the body rule) reads it without
# walking ProseMirror JSON itself.
#
# It is total over a document that never passed `RichText::Document#validate`
# (an MCP-authored or hand-edited row): a node that is not what is expected is
# skipped, never raised on, so a public page cannot be made a 500 by a stored
# body. Whether the body is right is `HasRichTextBody#body_errors_for`'s call,
# which asks `limit_errors` and `ragged?` of this.
class TableBody
  # A cell: `header` (a `tableHeader`), `align` (nil, "left", "center" or
  # "right"), `nodes` (the paragraph's inline JSON nodes, what
  # `RichText::HtmlRenderer#render_fragment` draws) and `text` (plain text, for
  # the length limit, the blank test and the editor's summary).
  Cell = Data.define(:header, :align, :nodes, :text)

  # Advice, not a refusal: a table this wide or this long is saved and the
  # editor says it may be hard to read on a phone.
  WARN_COLUMNS = 6
  WARN_ROWS = 40

  # The hard limits: what a save refuses (`limit_errors`).
  MAX_COLUMNS = 30
  MAX_ROWS = 500
  MAX_CELL = 2_000

  ALIGNS = %w[left center right].freeze

  # The grid a Table with no table yet shows in the editor: three columns by
  # three rows of empty cells, the first row headers (Claude Design's B5:
  # "Header row" is on by default). It is the editor's STARTING content
  # (`admin--rich-text--editor`'s `startingContent`), never stored by itself:
  # the form's body field stays empty until the editor's first real change,
  # so a Table nobody typed into saves nothing and its body stays blank.
  STARTING_ROWS = 3
  STARTING_COLUMNS = 3

  def self.starting_document
    rows = Array.new(STARTING_ROWS) do |row|
      cells = Array.new(STARTING_COLUMNS) { { "type" => row.zero? ? "tableHeader" : "tableCell", "content" => [ { "type" => "paragraph" } ] } }
      { "type" => "tableRow", "content" => cells }
    end
    { "type" => "doc", "content" => [ { "type" => "table", "content" => rows } ] }
  end

  def initialize(document)
    @document = document
  end

  # Array<Array<Cell>>: the first top-level table's rows, `[]` for a document
  # without one.
  def rows
    @rows ||= table_rows.map { |row| cells_of(row) }.freeze
  end

  def row_count = rows.size
  def column_count = rows.map(&:size).max || 0

  # `[rows, columns]`, what the editor's summary line says of a table.
  def shape = [ row_count, column_count ]

  # Every cell of the first row is a header (and there is a first row).
  def header_row? = rows.any? && rows.first.any? && rows.first.all?(&:header)

  # The first cell of every row is a header.
  def header_column? = rows.any? && rows.all? { |row| row.first&.header }

  # No cell has any text: a table of blank cells is a table nobody wrote.
  def blank? = rows.flatten.none? { |cell| cell.text.strip != "" }

  # Whether the rows have different numbers of cells. The node schema cannot
  # count (a content expression has no counts), so the body rule asks.
  def ragged? = rows.map(&:size).uniq.size > 1

  # Array<[Symbol, Integer]>: `[:columns, n]` from WARN_COLUMNS columns,
  # `[:rows, n]` from WARN_ROWS rows.
  def warnings
    found = []
    found << [ :columns, column_count ] if column_count >= WARN_COLUMNS
    found << [ :rows, row_count ] if row_count >= WARN_ROWS
    found
  end

  # Array<Symbol>: `:size` over MAX_COLUMNS columns or MAX_ROWS rows, `:cell`
  # when any cell is over MAX_CELL characters. Exactly the limit is fine.
  def limit_errors
    found = []
    found << :size if column_count > MAX_COLUMNS || row_count > MAX_ROWS
    found << :cell if rows.flatten.any? { |cell| cell.text.length > MAX_CELL }
    found
  end

  private

  def table_rows
    content = document_hash["content"]
    return [] unless content.is_a?(Array)

    table = content.find { |node| node.is_a?(Hash) && node["type"] == "table" }
    rows = table.is_a?(Hash) ? table["content"] : nil
    rows.is_a?(Array) ? rows.select { |row| row.is_a?(Hash) && row["type"] == "tableRow" } : []
  end

  def cells_of(row)
    content = row["content"]
    return [] unless content.is_a?(Array)

    content.filter_map do |cell|
      next unless cell.is_a?(Hash) && %w[tableHeader tableCell].include?(cell["type"])

      align = cell.dig("attrs", "align") if cell["attrs"].is_a?(Hash)
      nodes = inline_nodes(cell)
      Cell.new(header: cell["type"] == "tableHeader", align: (align if ALIGNS.include?(align)), nodes: nodes, text: text_of(nodes))
    end
  end

  # The cell's one paragraph's content; a hand-made cell with several
  # paragraphs reads as all their inline nodes in order.
  def inline_nodes(cell)
    paragraphs = cell["content"].is_a?(Array) ? cell["content"] : []
    paragraphs.flat_map { |paragraph| paragraph.is_a?(Hash) && paragraph["content"].is_a?(Array) ? paragraph["content"] : [] }
  end

  def text_of(nodes)
    nodes.map { |node| node.is_a?(Hash) ? (node["type"] == "hardBreak" ? " " : node["text"].to_s) : "" }.join
  end

  def document_hash
    hash = @document.respond_to?(:to_h) ? @document.to_h : {}
    hash.is_a?(Hash) ? hash : {}
  end
end
