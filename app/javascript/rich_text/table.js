import { Extension } from "@tiptap/core"
import { Table, TableRow, TableHeader, TableCell } from "@tiptap/extension-table"
import { Plugin, PluginKey, TextSelection } from "@tiptap/pm/state"
import { Decoration, DecorationSet } from "@tiptap/pm/view"
import { Fragment, Slice } from "@tiptap/pm/model"
import { TableMap, cellAround } from "@tiptap/pm/tables"

// The Table block's grid (table block spec decisions 3, 11 and 12): the
// table nodes configured to `RichText::BuiltIns`' -- `table` (`tableRow+`),
// `tableRow` (cells), `tableHeader` and `tableCell` (exactly one
// `paragraph`, an `align` of left, center or right) -- and the keys of
// Claude Design's B5. `extensions({ content: "table" })` (`schema.js`) puts
// these beside the inline marks; no other body's editor has them, so a
// post's or a text block's editor parses a pasted `<table>` into its text
// alone.
//
// prosemirror-tables needs `colspan`, `rowspan` and `colwidth` on every cell
// (its `TableMap` reads them), so the cells keep Tiptap's three; they are
// the editor's own and never stored: `storedDocument` drops them from what
// the editor writes into the hidden input, with an empty `align`. The
// server has no spans (a row's cells are one column each) and the editor
// offers no way to make one: no merge, no split, no resize (`resizable:
// false`).
//
// `cellMinWidth: 160` is the floor of a column in the editor (decision 12):
// Tiptap's `TableView` writes it into the colgroup and the table's
// `min-width`, so four columns fit the 640px editor column and a fifth makes
// the table wider than its box, `div.tableWrapper`, which scrolls sideways
// (`admin-rich-text.css`).

const ALIGNMENTS = [ "left", "center", "right" ]

// The column's alignment as the server writes it, `align-<value>`, so the
// grid shows it as the site does (`.admin-rich-text-table .align-*`). A
// pasted cell's `text-align` or `align` is read as Tiptap reads it, and an
// `align-*` class as the server writes it.
function alignAttribute() {
  return {
    default: null,
    parseHTML: (element) => {
      const named = ALIGNMENTS.find((value) => element.classList.contains(`align-${value}`))
      const styled = (element.style.textAlign || element.getAttribute("align") || "").trim().toLowerCase()
      return named || (ALIGNMENTS.includes(styled) ? styled : null)
    },
    renderHTML: (attributes) => (ALIGNMENTS.includes(attributes.align) ? { class: `align-${attributes.align}` } : {})
  }
}

// One paragraph per cell (decision 3), as the server's `content
// "paragraph"`: ProseMirror then cannot split a cell's paragraph in two
// (Enter is taken below in any case), and a paste is made inline first.
function cellExtension(base) {
  return base.extend({
    content: "paragraph",
    addAttributes() {
      return { ...this.parent?.(), align: alignAttribute() }
    }
  })
}

export const SchemaTableCell = cellExtension(TableCell)
export const SchemaTableHeader = cellExtension(TableHeader)
export const SchemaTableRow = TableRow
export const SchemaTable = Table.configure({ resizable: false, cellMinWidth: 160, allowTableNodeSelection: false })

// The cell around the selection's head, as a resolved position, or null.
function currentCell(state) {
  return cellAround(state.selection.$head)
}

// Enter: to the cell below, at the end of its text (a caret moved down a
// column lands where typing continues the cell). In the last row it stays
// where it is: Enter adds no paragraph and no row (Tab in the last cell is
// the way to a new row).
function cellBelow(state, dispatch) {
  const $cell = currentCell(state)
  if (!$cell) return false

  const table = $cell.node(-1)
  const tableStart = $cell.start(-1)
  const map = TableMap.get(table)
  const rect = map.findCell($cell.pos - tableStart)
  if (rect.bottom >= map.height) return true

  const below = tableStart + map.map[rect.bottom * map.width + rect.left]
  const node = state.doc.nodeAt(below)
  // The end of the cell's one paragraph: before the paragraph's and the cell's closing tokens.
  if (dispatch) dispatch(state.tr.setSelection(TextSelection.create(state.doc, below + node.nodeSize - 2)).scrollIntoView())
  return true
}

// A paste into a cell keeps inline content only: every textblock the
// clipboard held (paragraphs, list items, a pasted table's cells) becomes
// one line of the cell, the lines joined by hard breaks, its marks kept
// (they are this schema's already: the clipboard was parsed against it).
// Done in `transformPasted`, before prosemirror-tables' own `handlePaste`,
// so a pasted table never becomes cells of this one either: the grid's
// shape changes only through its own controls.
export function inlineSlice(slice, schema) {
  if (slice.content.childCount === 0 || slice.content.firstChild.isInline) return slice

  const lines = []
  slice.content.descendants((node) => {
    if (!node.isTextblock) return true
    if (node.content.size > 0) lines.push(node.content)
    return false
  })

  const nodes = []
  lines.forEach((line, index) => {
    if (index > 0) nodes.push(schema.nodes.hardBreak.create())
    line.forEach((node) => nodes.push(node))
  })
  return new Slice(Fragment.fromArray(nodes), 0, 0)
}

// The grid's keys (Claude Design's B5). Tab, Shift+Tab (and Tab in the last
// cell adding a row) are the Table extension's own; Shift+Enter is
// HardBreak's; the arrows leave a cell only at its text's start or end,
// prosemirror-tables' default. Here: Enter down, Esc out of the grid. A
// priority above the core keymap's, whose Enter would try to split the
// paragraph.
export const TableKeys = Extension.create({
  name: "tableKeys",
  priority: 1000,

  addKeyboardShortcuts() {
    return {
      Enter: () => cellBelow(this.editor.state, this.editor.view.dispatch),
      Escape: () => this.editor.commands.blur()
    }
  },

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: new PluginKey("tableCellPaste"),
        props: { transformPasted: (slice, view) => inlineSlice(slice, view.state.schema) }
      }),
      // The cell the caret is in carries `is-current-cell`, a decoration (the
      // cells are ProseMirror's to draw, so no script may set a class on
      // one): the card outlines it while the grid has the focus
      // (`.ProseMirror-focused`, `admin-rich-text.css`). The strips invert its
      // letter and number from the same selection (`admin--editor--table`,
      // `selectedCell`).
      new Plugin({
        key: new PluginKey("tableCurrentCell"),
        props: {
          decorations: (state) => {
            const $cell = cellAround(state.selection.$head)
            const cell = $cell && state.doc.nodeAt($cell.pos)
            return cell ? DecorationSet.create(state.doc, [ Decoration.node($cell.pos, $cell.pos + cell.nodeSize, { class: "is-current-cell" }) ]) : null
          }
        }
      })
    ]
  }
})

// A row added in any way (Tab in the last cell, Insert above or below, the
// "+" and "Add row") takes its column's alignment (decision 5: the editor
// writes whole columns, and a cell never has an alignment its column does
// not have). prosemirror-tables makes a new row's cells with no attributes,
// so they would read as left in a right-aligned column. A row is new when the
// table it is in after the change holds a row node that was not in the table
// before (ProseMirror keeps the node objects of what a step did not touch), and
// its column's alignment is the first row's as it was before the change.
export const TableColumnAlignment = Extension.create({
  name: "tableColumnAlignment",

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: new PluginKey("tableColumnAlignment"),
        appendTransaction: (transactions, oldState, newState) => {
          if (!transactions.some((transaction) => transaction.docChanged)) return null

          const before = tableNode(oldState.doc)
          const after = tableNode(newState.doc)
          if (!before || !after || after.childCount <= before.childCount) return null

          const kept = new Set()
          before.forEach((row) => kept.add(row))
          const aligns = []
          before.firstChild.forEach((cell) => aligns.push(alignOf(cell)))

          let tr = null
          let rowPosition = TABLE_START
          after.forEach((row) => {
            if (!kept.has(row)) {
              row.forEach((cell, offset, column) => {
                const align = aligns[column] ?? null
                if (alignOf(cell) === align) return
                tr ||= newState.tr
                tr.setNodeMarkup(rowPosition + 1 + offset, null, { ...cell.attrs, align })
              })
            }
            rowPosition += row.nodeSize
          })
          return tr
        }
      })
    ]
  }
})

// --- The grid, by row and column ------------------------------------------
//
// What `admin--editor--table` (the rows', columns' and header controls around
// the grid) reads and writes. The table is the document's one top-level node
// (`Document.extend({ content: "table?" })`, `schema.js`), so it starts at 0
// and its first row at 1. Rows and columns count from zero; a table here has
// no spans, so a row's n-th cell is column n.
const TABLE_START = 1

function alignOf(cell) {
  return ALIGNMENTS.includes(cell.attrs.align) ? cell.attrs.align : null
}

// The document's table node, or null.
export function tableNode(doc) {
  const first = doc.firstChild
  return first && first.type.name === "table" ? first : null
}

// `{ rows, columns }` of the document's table, `{ rows: 0, columns: 0 }` without one.
export function gridShape(doc) {
  const table = tableNode(doc)
  if (!table) return { rows: 0, columns: 0 }
  return { rows: table.childCount, columns: TableMap.get(table).width }
}

// The position of the cell node at (row, column), or null.
export function cellPosition(doc, row, column) {
  const table = tableNode(doc)
  if (!table) return null
  const map = TableMap.get(table)
  if (row < 0 || column < 0 || row >= map.height || column >= map.width) return null
  return TABLE_START + map.map[row * map.width + column]
}

// A position inside the cell's one paragraph, where a caret can be: at the
// end of its text.
export function insideCell(doc, row, column) {
  const position = cellPosition(doc, row, column)
  if (position === null) return null
  return position + doc.nodeAt(position).nodeSize - 2
}

// `{ row, column }` of the cell the selection's head is in, or null.
export function selectedCell(state) {
  const $cell = cellAround(state.selection.$head)
  const table = tableNode(state.doc)
  if (!$cell || !table) return null
  const rect = TableMap.get(table).findCell($cell.pos - TABLE_START)
  return { row: rect.top, column: rect.left }
}

// Whether a row's (or a column's) cells hold any text: what Delete asks
// first for (Claude Design's B5).
export function rowHasText(doc, row) {
  const table = tableNode(doc)
  return Boolean(table && row < table.childCount && table.child(row).textContent.trim() !== "")
}

export function columnHasText(doc, column) {
  const table = tableNode(doc)
  if (!table) return false
  let found = false
  table.forEach((row) => {
    if (column < row.childCount && row.child(column).textContent.trim() !== "") found = true
  })
  return found
}

// The column's alignment as the column menu shows it: its first cell's
// ("left" for none: absent is left, decision 5).
export function columnAlign(doc, column) {
  const table = tableNode(doc)
  const cell = table && column < table.firstChild.childCount ? table.firstChild.child(column) : null
  return (cell && alignOf(cell)) || "left"
}

// Every cell of the column to `align`; "left" is written as no alignment,
// absent being left (decision 5), so the stored cell carries no attribute.
export function alignColumn(tr, column, align) {
  const table = tableNode(tr.doc)
  if (!table) return tr
  const value = align === "left" ? null : align
  let rowPosition = TABLE_START
  table.forEach((row) => {
    let cellPosition = rowPosition + 1
    row.forEach((cell, _offset, index) => {
      if (index === column && alignOf(cell) !== value) tr.setNodeMarkup(cellPosition, null, { ...cell.attrs, align: value })
      cellPosition += cell.nodeSize
    })
    rowPosition += row.nodeSize
  })
  return tr
}

// "Header row" and "First column as header" as the cells say (decision 4,
// and `TableBody#header_row?` / `#header_column?`, the server's reading):
// every cell of the first row is a header; the first cell of every row is.
export function headerState(doc) {
  const table = tableNode(doc)
  if (!table) return { row: false, column: false }
  let column = true
  table.forEach((row) => { if (row.firstChild?.type.name !== "tableHeader") column = false })
  let row = table.firstChild.childCount > 0
  table.firstChild.forEach((cell) => { if (cell.type.name !== "tableHeader") row = false })
  return { row, column }
}

// The cells' kinds made what the two switches say: a cell is a header when
// it is in the first row with "Header row" on, or in the first column with
// "First column as header" on, and a plain cell otherwise. Run with the
// switches as they were BEFORE a row or column is inserted, moved or deleted,
// so a header row stays the table's first row whatever moved (a row moved
// down from the top becomes a body row, and the row that is now first becomes
// the header), and after either switch is pressed. Attributes (the
// alignment) are kept.
export function applyHeaders(tr, { row: headerRow, column: headerColumn }) {
  const table = tableNode(tr.doc)
  if (!table) return tr
  const { tableHeader, tableCell } = tr.doc.type.schema.nodes
  let rowPosition = TABLE_START
  table.forEach((row, _offset, rowIndex) => {
    let cellPosition = rowPosition + 1
    row.forEach((cell, _cellOffset, columnIndex) => {
      const type = (headerRow && rowIndex === 0) || (headerColumn && columnIndex === 0) ? tableHeader : tableCell
      if (cell.type !== type) tr.setNodeMarkup(cellPosition, type, cell.attrs)
      cellPosition += cell.nodeSize
    })
    rowPosition += row.nodeSize
  })
  return tr
}

// What the editor writes into the hidden input for a table body: the
// document without the editor's own cell attributes (see the top of this
// file), and an editor emptied of its table as an empty document, the one
// form of "no table" the server's rule takes (`{ type: "doc", content: [] }`).
export function storedDocument(json) {
  const content = Array.isArray(json?.content) ? json.content : []
  return { type: "doc", content: content.map(storedNode) }
}

function storedNode(node) {
  const stored = { ...node }
  if (node.type === "tableCell" || node.type === "tableHeader") {
    const align = node.attrs?.align
    delete stored.attrs
    if (ALIGNMENTS.includes(align)) stored.attrs = { align }
  }
  if (Array.isArray(node.content)) stored.content = node.content.map(storedNode)
  return stored
}
