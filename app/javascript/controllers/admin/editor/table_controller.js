import { Controller } from "@hotwired/stimulus"
import { TextSelection } from "@tiptap/pm/state"
import { addRowBefore, addRowAfter, addColumnBefore, addColumnAfter, deleteRow, deleteColumn, moveTableRow, moveTableColumn } from "@tiptap/pm/tables"
import { editorOf } from "rich_text/editors"
import {
  tableNode, gridShape, cellPosition, insideCell, selectedCell, rowHasText, columnHasText,
  columnAlign, alignColumn, headerState, applyHeaders
} from "rich_text/table"
import { messages } from "i18n/messages"

// The Table block's grid controls (`Admin::EditorScreen::TableControlsComponent`,
// table block spec decisions 4, 5, 7 and 12; Claude Design's B5): the two
// header switches, the warning line, the current row's and column's "⋯"
// menus and "+", and "Add row".
//
// THE GRID IS THE EDITOR'S. Every control works through the Tiptap editor of
// the `admin--rich-text--editor` inside this element (found through
// `rich_text/editors`, and heard of through its `attached` and `detached`
// events: never an outlet), as ONE editor transaction each: the editor then
// writes the hidden input and the form's autosave sends it, exactly as for
// typing, so a change here is claimed, queued, refused when stale or held and
// merged by live refresh like any other edit of the body. Undo undoes it. And
// the editor's first real change is what writes a starting grid into the
// field (`startingContent`): a control pressed on a new Table writes it too.
//
// THE CURRENT CELL. The controls are for one row and one column: those of
// the cell under the pointer, else the cell the caret is in. They show while
// the pointer is over this element or the focus is in it, at the grid's edge
// on that row and column (`place`), and stay put while one of their menus is
// open, so a menu never moves under the pointer. Esc in the grid leaves it to
// the row's "⋯" (the keyboard's way to the controls: Tab moves between cells
// inside the grid), and Tab goes on from there to the column's "⋯" and the
// two "+".
//
// HEADERS ARE THE FIRST ROW AND THE FIRST COLUMN (decision 4). The switches
// make the cells of the first row, and of the first column, headers or not
// (`applyHeaders`); and a row or a column inserted, moved or deleted keeps
// them where they were, so "Header row" stays the table's first row whatever
// is moved above or out of it. Their state is read back from the cells after
// every change, as the warning is (`refresh`).
export default class extends Controller {
  static targets = [ "headerRow", "headerColumn", "warning", "rowControls", "columnControls", "addColumn", "addRowHere" ]

  static values = {
    warnColumns: Number,
    warnRows: Number,
    rowDialog: String,
    columnDialog: String,
    // What "Add row" inserts into a grid emptied of its table: the starting
    // grid (`TableBody.starting_document`), the server's one copy of it.
    startingGrid: Object
  }

  connect() {
    this.editor = null
    this.current = null
    this.hovered = false
    this.focused = false
    this.changed = () => this.refresh()
    this.scrolled = () => this.place()
    this.hideControls()
    this.element.addEventListener("scroll", this.scrolled, true)
    this.use(editorOf(this.element.querySelector("[data-controller~='admin--rich-text--editor']")))
  }

  disconnect() {
    this.element.removeEventListener("scroll", this.scrolled, true)
    this.withdrawDialog()
    this.use(null)
    this.hideControls()
  }

  // `admin--rich-text--editor:attached` / `:detached`, from the editor inside.
  attach(event) {
    this.use(event.detail?.editor || null)
  }

  detach() {
    this.use(null)
  }

  use(editor) {
    if (this.editor === editor) return
    this.editor?.off("transaction", this.changed)
    this.editor = editor
    this.current = null
    this.editor?.on("transaction", this.changed)
    this.refresh()
  }

  // The editor, when the grid can be changed now: not before it is mounted,
  // not once it is read-only (a stored body it cannot show, a form frozen in
  // place by a hold).
  usable() {
    return this.editor && !this.editor.isDestroyed && this.editor.isEditable ? this.editor : null
  }

  // --- What the page says of the grid ---------------------------------------

  // After every transaction of the editor (typing, a control, an undo, a
  // suggestion used): the switches and the warning as the cells say, then the
  // current cell, the menus and their places.
  refresh() {
    const doc = this.editor?.state.doc
    if (!doc) return this.hideControls()

    const headers = headerState(doc)
    if (this.hasHeaderRowTarget) this.headerRowTarget.checked = headers.row
    if (this.hasHeaderColumnTarget) this.headerColumnTarget.checked = headers.column
    this.refreshWarning(gridShape(doc))

    if (this.editor.isFocused) this.current = selectedCell(this.editor.state) || this.current
    this.current = this.clamped(this.current)
    this.place()
  }

  // The warning line (decision 7): from 6 columns, from 40 rows, both in one
  // alert, in the server's words (`data-messages`).
  refreshWarning({ rows, columns }) {
    if (!this.hasWarningTarget) return
    const text = messages(this.element)
    const sentences = []
    if (columns >= this.warnColumnsValue) sentences.push(text.t("components.editor_screen.table_controls.warning.columns", { count: columns }))
    if (rows >= this.warnRowsValue) sentences.push(text.t("components.editor_screen.table_controls.warning.rows", { count: rows }))
    const sentence = sentences.join(" ")
    if (this.warningTarget.textContent !== sentence) this.warningTarget.textContent = sentence
    this.warningTarget.hidden = sentence === ""
  }

  // A current cell that is still in the grid: the last row or column when a
  // delete took the one it was in, nothing when there is no table.
  clamped(cell) {
    const { rows, columns } = gridShape(this.editor.state.doc)
    if (!cell || rows === 0) return null
    return { row: Math.min(cell.row, rows - 1), column: Math.min(cell.column, columns - 1) }
  }

  // --- Showing the controls -------------------------------------------------

  hover(event) {
    if (this.menuOpen()) return
    const element = event.target.closest?.("td, th")
    const grid = this.gridElement()
    if (!element || !grid || !grid.contains(element) || !this.editor) return

    const row = element.parentElement
    const cell = { row: Array.prototype.indexOf.call(row.parentElement.children, row), column: Array.prototype.indexOf.call(row.children, element) }
    if (this.current?.row === cell.row && this.current?.column === cell.column) return
    this.current = this.clamped(cell)
    this.place()
  }

  enter() {
    this.hovered = true
    this.place()
  }

  leave() {
    this.hovered = false
    this.place()
  }

  focusIn() {
    this.focused = true
    if (this.editor?.isFocused) this.current = this.clamped(selectedCell(this.editor.state) || this.current)
    this.place()
  }

  focusOut(event) {
    this.focused = Boolean(event.relatedTarget && this.element.contains(event.relatedTarget))
    this.place()
  }

  // Esc in the grid (the editor has let go of it, `rich_text/table.js`):
  // the focus goes to the row's "⋯", from which Tab reaches the rest.
  keydown(event) {
    if (event.key !== "Escape" || !event.target.closest?.(".ProseMirror") || !this.current) return
    this.focused = true
    this.place()
    const button = this.rowControlsTarget.querySelector("button[aria-haspopup]")
    if (button && !this.rowControlsTarget.hidden) button.focus()
  }

  // The button of the row's or the column's menu while its panel is open.
  openMenu() {
    return this.element.querySelector("[data-admin--editor--table-target$='Controls'] [aria-expanded='true']")
  }

  menuOpen() {
    return Boolean(this.openMenu())
  }

  floating() {
    return [ this.rowControlsTarget, this.columnControlsTarget, this.addColumnTarget, this.addRowHereTarget ]
  }

  hideControls() {
    this.floating().forEach((element) => {
      element.hidden = true
    })
  }

  gridElement() {
    return this.editor && !this.editor.isDestroyed ? this.editor.view.dom : null
  }

  // Puts the four controls on the grid's edges at the current row and
  // column: the row's "⋯" on the grid's left edge, the column's "⋯" on its
  // top edge, the "+" for a column at the row's end and the "+" for a row
  // under the column, each centred on its edge (`FLOATING_CLASS`). The table
  // scrolls sideways in its box (`.tableWrapper`), so the edges are the box's
  // where the table is wider, and a column scrolled out of the box has no
  // controls until it is scrolled back.
  place() {
    const editor = this.usable()
    const show = editor && this.current && (this.hovered || this.focused || this.menuOpen())
    if (!show) return this.hideControls()

    const { row, column } = this.current
    const doc = editor.state.doc
    const rowCell = this.cellElement(doc, row, 0)
    const columnCell = this.cellElement(doc, 0, column)
    const box = this.gridElement()?.querySelector(".tableWrapper")
    const table = box?.querySelector("table")
    if (!rowCell || !columnCell || !table) return this.hideControls()

    const base = this.element.getBoundingClientRect()
    const visible = box.getBoundingClientRect()
    const edges = table.getBoundingClientRect()
    const rowBox = rowCell.getBoundingClientRect()
    const columnBox = columnCell.getBoundingClientRect()
    const middleOfRow = rowBox.top + rowBox.height / 2
    const middleOfColumn = columnBox.left + columnBox.width / 2
    const columnShown = middleOfColumn >= visible.left && middleOfColumn <= visible.right

    // While a menu is open the other controls step aside: each is its own
    // layer on the grid, and one drawn later would cover the open panel.
    const open = this.openMenu()?.closest("[data-admin--editor--table-target]") || null
    const alone = (element) => !open || element === open

    this.put(this.rowControlsTarget, Math.max(edges.left, visible.left), middleOfRow, base, alone(this.rowControlsTarget))
    this.put(this.columnControlsTarget, middleOfColumn, edges.top, base, columnShown && alone(this.columnControlsTarget))
    this.put(this.addColumnTarget, Math.min(edges.right, visible.right), middleOfRow, base, alone(this.addColumnTarget))
    this.put(this.addRowHereTarget, middleOfColumn, edges.bottom, base, columnShown && alone(this.addRowHereTarget))
    // Not while a menu is open: its item's own click is still on its way to
    // the menu, which closes only for an item that is not disabled, and the
    // change it made could disable it (Move up on the row that is now the
    // first). The focus coming back to the grid refreshes them.
    if (!open) this.refreshMenus(doc)
  }

  put(element, x, y, base, shown) {
    element.style.left = `${x - base.left}px`
    element.style.top = `${y - base.top}px`
    element.hidden = !shown
  }

  cellElement(doc, row, column) {
    const position = cellPosition(doc, row, column)
    if (position === null) return null
    const node = this.editor.view.nodeDOM(position)
    return node instanceof Element ? node : null
  }

  // What each item can do for the current row and column: a first row
  // cannot move up, a table's one row cannot be deleted (a grid is emptied
  // by selecting its cells, as any text is). The column's alignment is
  // checked, as a radio item (`menuitemradio`, set here after the menu has
  // made every item a `menuitem`).
  refreshMenus(doc) {
    const { rows, columns } = gridShape(doc)
    const { row, column } = this.current
    const off = {
      move_up: row === 0,
      move_down: row === rows - 1,
      delete_row: rows === 1,
      move_left: column === 0,
      move_right: column === columns - 1,
      delete_column: columns === 1
    }
    this.element.querySelectorAll("[data-table-command]").forEach((item) => {
      item.disabled = Boolean(off[item.dataset.tableCommand])
    })
    const align = columnAlign(doc, column)
    this.element.querySelectorAll("[data-table-align]").forEach((item) => {
      item.setAttribute("role", "menuitemradio")
      item.setAttribute("aria-checked", item.dataset.tableAlign === align ? "true" : "false")
    })
  }

  // --- The switches -----------------------------------------------------------

  headerRow(event) {
    this.setHeaders({ row: event.target.checked })
  }

  headerColumn(event) {
    this.setHeaders({ column: event.target.checked })
  }

  // The focus stays on the switch (no `focus()` in the chain): a keyboard
  // user goes on from where they were.
  setHeaders(change) {
    const editor = this.usable()
    if (!editor || !tableNode(editor.state.doc)) return this.refresh()
    const headers = { ...headerState(editor.state.doc), ...change }
    editor.chain().command(({ tr }) => {
      applyHeaders(tr, headers)
      return true
    }).run()
    this.refresh()
  }

  // --- Rows and columns ---------------------------------------------------------

  insertRowAbove() { this.structural(addRowBefore, ({ row, column }) => ({ row, column })) }
  insertRowBelow() { this.structural(addRowAfter, ({ row, column }) => ({ row: row + 1, column })) }
  moveRowUp() { this.move("row", -1) }
  moveRowDown() { this.move("row", 1) }
  insertColumnLeft() { this.structural(addColumnBefore, ({ row, column }) => ({ row, column })) }
  insertColumnRight() { this.structural(addColumnAfter, ({ row, column }) => ({ row, column: column + 1 })) }
  moveColumnLeft() { this.move("column", -1) }
  moveColumnRight() { this.move("column", 1) }

  // The "+" at a row's end: a column after the last. The "+" under a column
  // and "Add row": a row after the last; into a grid emptied of its table,
  // the starting grid again.
  addColumn() {
    const editor = this.usable()
    if (!editor) return
    const { columns } = gridShape(editor.state.doc)
    if (columns === 0) return
    const row = this.current?.row ?? 0
    this.structural(addColumnAfter, () => ({ row, column: columns }), { row, column: columns - 1 })
  }

  addRow() {
    const editor = this.usable()
    if (!editor) return
    const { rows } = gridShape(editor.state.doc)
    if (rows === 0) {
      editor.chain().setContent(this.startingGridValue, { emitUpdate: true }).focus("start").run()
      return
    }
    const column = this.current?.column ?? 0
    this.structural(addRowAfter, () => ({ row: rows, column }), { row: rows - 1, column })
  }

  move(axis, step) {
    if (!this.current) return
    const from = this.current[axis]
    const command = axis === "row" ? moveTableRow : moveTableColumn
    this.structural(command({ from, to: from + step, select: false }), (cell) => ({ ...cell, [axis]: from + step }))
  }

  deleteRow() {
    const editor = this.usable()
    if (!editor || !this.current) return
    const { row, column } = this.current
    const remove = () => this.structural(deleteRow, () => ({ row, column }), { row, column })
    rowHasText(editor.state.doc, row) ? this.confirm(this.rowDialogValue, remove, { row, column }) : remove()
  }

  deleteColumn() {
    const editor = this.usable()
    if (!editor || !this.current) return
    const { row, column } = this.current
    const remove = () => this.structural(deleteColumn, () => ({ row, column }), { row, column })
    columnHasText(editor.state.doc, column) ? this.confirm(this.columnDialogValue, remove, { row, column }) : remove()
  }

  // Align: Left, Centre, Right, for every cell of the current column.
  align({ params }) {
    const editor = this.usable()
    if (!editor || !this.current) return
    const { row, column } = this.current
    const at = insideCell(editor.state.doc, row, column)
    if (at === null) return
    editor.chain().focus().setTextSelection(at).command(({ tr }) => {
      alignColumn(tr, column, params.align)
      return true
    }).run()
  }

  // One transaction: the caret into `cell` (the current one unless said),
  // the prosemirror-tables command, which acts on the selection's cell, the
  // header kinds as the switches said before (see the top of this file), and
  // the caret into the cell `after` names in the new shape. `focus()` comes
  // first in the chain: with no position it puts back the selection the
  // editor had, so anywhere later it would undo the selection set here.
  structural(command, after, cell = this.current) {
    const editor = this.usable()
    if (!editor || !cell) return
    const at = insideCell(editor.state.doc, cell.row, cell.column)
    if (at === null) return
    const headers = headerState(editor.state.doc)
    const target = after(cell)
    editor.chain().focus().setTextSelection(at)
      .command(({ state, dispatch }) => command(state, dispatch))
      .command(({ tr }) => {
        applyHeaders(tr, headers)
        const position = insideCell(tr.doc, target.row, target.column)
        if (position !== null) tr.setSelection(TextSelection.create(tr.doc, position))
        return true
      })
      .run()
    this.current = this.clamped(target)
    this.place()
  }

  // --- Asking first ---------------------------------------------------------------

  // Opens the confirm dialog (`TableDeleteDialogsComponent`, outside the form,
  // by id) and runs `action` if it closes with "delete"; Cancel and Escape
  // put the focus back into the cell. The cell is the one asked about,
  // whatever the pointer does meanwhile.
  confirm(id, action, cell) {
    const dialog = document.getElementById(id)
    if (!dialog || dialog.open) return
    this.withdrawDialog()
    dialog.returnValue = ""
    const closed = () => {
      this.withdrawDialog()
      if (dialog.returnValue === "delete") {
        this.current = cell
        action()
      } else {
        this.focusCell(cell)
      }
    }
    dialog.addEventListener("close", closed)
    this.dialogListener = { dialog, closed }
    dialog.showModal()
  }

  withdrawDialog() {
    if (!this.dialogListener) return
    this.dialogListener.dialog.removeEventListener("close", this.dialogListener.closed)
    this.dialogListener = null
  }

  focusCell(cell) {
    const editor = this.usable()
    const at = editor && cell ? insideCell(editor.state.doc, cell.row, cell.column) : null
    if (at !== null) editor.chain().focus().setTextSelection(at).run()
  }
}
