import { Extension } from "@tiptap/core"
import { Table, TableRow, TableHeader, TableCell } from "@tiptap/extension-table"
import { Plugin, PluginKey, TextSelection } from "@tiptap/pm/state"
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
      })
    ]
  }
})

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
