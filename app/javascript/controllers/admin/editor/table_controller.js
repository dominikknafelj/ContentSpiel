import { Controller } from "@hotwired/stimulus"
import { TextSelection } from "@tiptap/pm/state"
import { addRowBefore, addRowAfter, addColumnBefore, addColumnAfter, deleteRow, deleteColumn, moveTableRow, moveTableColumn } from "@tiptap/pm/tables"
import { editorOf } from "rich_text/editors"
import {
  tableNode, gridShape, insideCell, selectedCell, rowHasText, columnHasText,
  columnAlign, alignColumn, headerState, applyHeaders
} from "rich_text/table"
import { messages } from "i18n/messages"

// The Table block's grid controls (`Admin::EditorScreen::TableControlsComponent`,
// table block spec decisions 4, 5, 7 and 12; Claude Design's B5; the strips
// are the owner's option B of 2026-10-29, "Row and column strips"): the two
// header switches, the warning line, a strip of column letters above the grid
// and of row numbers to its left (each letter and number the button of that
// column's or row's menu), a dashed "+" at the end of each strip, and "Add row".
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
// THE STRIPS. One entry per column and per row, cloned from the server's
// `<template>`s (`columnTemplate`, `rowTemplate`: a menu with every item) as
// the grid grows, removed from the end as it shrinks, and named here ("Column
// B actions", "Row 3 actions", the server's words in `data-messages`). Each
// entry is placed on its cell's box, measured (`place`): a row's height is its
// text's, and a table wider than its box scrolls sideways in it
// (`.tableWrapper`), so a letter follows its column and is cut at the box's
// edges, gone while its column is scrolled out. They stand in the grid box's
// padding (`admin-rich-text.css`), so nothing is drawn over a cell's text. A
// menu acts on ITS column or row (`data-table-column`, `data-table-row` on the
// entry), whatever the caret does meanwhile.
//
// THE CURRENT CELL is the one the caret is in (or was last in), and a letter
// or number pressed makes its column or row the current one. Its letter and
// number are inverted and carry `aria-current` (a menu button's own state is
// `aria-expanded`, so not `aria-pressed`); the cell itself is outlined by the
// editor's decoration while the grid has the focus (`rich_text/table.js`).
//
// THE KEYBOARD. Tab moves between cells inside the grid, so Esc leaves it to
// the current column's letter; each strip is one stop for Tab (a roving
// tabindex: the current letter or number, or the one the arrow keys moved to),
// Left and Right move along the letters, Up and Down along the numbers, and
// Enter, Space or a press opens the menu. Tab goes on from the letters to the
// column's "+", the numbers, the row's "+" and "Add row".
//
// HEADERS ARE THE FIRST ROW AND THE FIRST COLUMN (decision 4). The switches
// make the cells of the first row, and of the first column, headers or not
// (`applyHeaders`); and a row or a column inserted, moved or deleted keeps
// them where they were, so "Header row" stays the table's first row whatever
// is moved above or out of it. Their state is read back from the cells after
// every change, as the warning is (`refresh`).
export default class extends Controller {
  static targets = [ "headerRow", "headerColumn", "warning", "corner", "columnStrip", "rowStrip", "addColumn", "addRowHere", "columnTemplate", "rowTemplate" ]

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
    // What the strips were last drawn for (`place`): the grid's shape and
    // alignments, and the boxes measured. A pass that finds both unchanged
    // writes nothing but the current cell's marks.
    this.drawn = { shape: null, menus: null, geometry: null }
    this.marked = { column: null, row: null }
    this.stops = { column: null, row: null }
    this.frame = null
    this.changed = () => this.refresh()
    this.scrolled = () => this.schedule()
    // A row grows as its text wraps and the card follows the window: the
    // strips are placed again whenever the grid's box changes size, in the
    // same one pass per frame as typing and scrolling (`schedule`).
    this.resized = new ResizeObserver(() => this.schedule())
    this.resized.observe(this.element)
    this.hideStrips()
    this.element.addEventListener("scroll", this.scrolled, true)
    this.use(editorOf(this.element.querySelector("[data-controller~='admin--rich-text--editor']")))
  }

  disconnect() {
    this.element.removeEventListener("scroll", this.scrolled, true)
    this.resized.disconnect()
    if (this.frame !== null) cancelAnimationFrame(this.frame)
    this.frame = null
    this.withdrawDialog()
    this.use(null)
    this.hideStrips()
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
    if (this.editor && !this.editor.isDestroyed) this.resized.unobserve(this.editor.view.dom)
    this.editor = editor
    this.current = null
    this.editor?.on("transaction", this.changed)
    if (this.editor && !this.editor.isDestroyed) this.resized.observe(this.editor.view.dom)
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
  // current cell and the strips.
  refresh() {
    const doc = this.editor?.state.doc
    if (!doc) return this.hideStrips()

    const headers = headerState(doc)
    if (this.hasHeaderRowTarget) this.headerRowTarget.checked = headers.row
    if (this.hasHeaderColumnTarget) this.headerColumnTarget.checked = headers.column
    this.refreshWarning(gridShape(doc))

    if (this.editor.isFocused) this.current = selectedCell(this.editor.state) || this.current
    this.current = this.clamped(this.current)
    this.schedule()
  }

  // One pass of `place` in the next frame, however many transactions,
  // scrolls and resizes ask for one before it (typing a word is a
  // transaction per character). A control that needs the strips right at
  // once (a menu's command, a letter given the focus) calls `place` itself.
  schedule() {
    if (this.frame !== null) return
    this.frame = requestAnimationFrame(() => {
      this.frame = null
      this.place()
    })
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

  // --- The current cell -------------------------------------------------------

  focusIn() {
    if (this.editor?.isFocused) this.current = this.clamped(selectedCell(this.editor.state) || this.current)
    this.place()
  }

  // A press on a strip's letter or number (not on an item of its menu, which
  // places the caret itself): that column, or that row, is the current one.
  choose(event) {
    const editor = this.usable()
    if (!editor || !event.target.closest?.(".admin-table-strip-button")) return
    const cell = this.cellOf(event)
    if (!cell) return
    this.current = this.clamped(cell)
    this.place()
  }

  // The cell a strip's menu acts on: its own column or row, and the current
  // cell's other coordinate (the first when there is none).
  cellOf(event) {
    const entry = event?.target?.closest?.(".admin-table-strip-entry")
    const row = entry?.dataset.tableRow
    const column = entry?.dataset.tableColumn
    if (row === undefined && column === undefined) return this.current
    return {
      row: row !== undefined ? Number(row) : (this.current?.row ?? 0),
      column: column !== undefined ? Number(column) : (this.current?.column ?? 0)
    }
  }

  // A click anywhere in the controls: once a menu has closed (its item's click
  // has reached its panel), the menus are made right for the grid as it is.
  settle() {
    if (!this.menuOpen()) this.place()
  }

  // --- The keyboard -------------------------------------------------------------

  keydown(event) {
    if (event.key === "Escape" && event.target.closest?.(".ProseMirror")) return this.leaveGrid()
    this.moveAlong(event)
  }

  // Esc in the grid (the editor has let go of it, `rich_text/table.js`): the
  // focus goes to the current column's letter, from which Tab reaches the rest.
  leaveGrid() {
    if (!this.current) return
    this.focusEntry("column", this.current.column)
  }

  // The arrow keys along a strip, on a letter or a number whose menu is
  // closed (an open menu's arrows are its own, `admin--ui--menu`).
  moveAlong(event) {
    const button = event.target
    if (!button.matches?.(".admin-table-strip-button") || button.getAttribute("aria-expanded") === "true") return
    const columns = this.columnStripTarget.contains(button)
    const steps = columns ? { ArrowLeft: -1, ArrowRight: 1 } : { ArrowUp: -1, ArrowDown: 1 }
    const step = steps[event.key]
    if (step === undefined) return
    event.preventDefault()
    const entries = this.entries(columns ? "column" : "row")
    const index = entries.indexOf(button.closest(".admin-table-strip-entry"))
    const next = index + step
    if (next >= 0 && next < entries.length) this.focusEntry(columns ? "column" : "row", next)
  }

  // A letter or a number given the focus, its column scrolled into the box
  // first (a letter whose column is scrolled out is not shown). The focus
  // makes it its strip's one Tab stop (`markCurrent`).
  focusEntry(axis, index) {
    if (axis === "column") this.revealColumn(index)
    this.place()
    const button = this.entries(axis)[index]?.querySelector(".admin-table-strip-button")
    if (!button || button.closest("[hidden]")) return
    button.focus()
    this.markCurrent()
  }

  // The box scrolled sideways so the column's cell is wholly in it. Measured
  // as boxes on the screen: a cell's `offsetLeft` is counted from the editor
  // (its `offsetParent`, padding and strips included), not from the box.
  revealColumn(index) {
    const box = this.wrapperElement()
    const cell = box?.querySelector("table")?.rows[0]?.cells[index]
    if (!cell) return
    const visible = box.getBoundingClientRect()
    const { left, right } = cell.getBoundingClientRect()
    if (left < visible.left) box.scrollLeft -= visible.left - left
    else if (right > visible.right) box.scrollLeft += right - visible.right
  }

  // --- The strips -------------------------------------------------------------------

  // The button of a strip's menu while its panel is open.
  openMenu() {
    return this.element.querySelector(".admin-table-strip-entry [aria-expanded='true']")
  }

  menuOpen() {
    return Boolean(this.openMenu())
  }

  entries(axis) {
    const strip = axis === "column" ? this.columnStripTarget : this.rowStripTarget
    return Array.from(strip.children)
  }

  // Everything of the strips hidden, and nothing remembered of where they
  // stood, so the next `place` draws them whole. Guarded: a controller taken
  // off its element in place (its `data-controller` removed) finds no target.
  hideStrips() {
    [ "corner", "columnStrip", "rowStrip", "addColumn", "addRowHere" ].forEach((name) => {
      if (this[`has${name[0].toUpperCase()}${name.slice(1)}Target`]) this[`${name}Target`].hidden = true
    })
    if (this.drawn) this.drawn.geometry = null
  }

  gridElement() {
    return this.editor && !this.editor.isDestroyed ? this.editor.view.dom : null
  }

  wrapperElement() {
    return this.gridElement()?.querySelector(".tableWrapper") || null
  }

  // As many entries as the grid has columns and rows: the missing ones cloned
  // from the template and named, the extra ones taken off the end. An entry
  // stands for a place, not a column's content (moving a column moves its
  // text, not its letter), so an entry kept is never renamed.
  syncEntries(axis, count) {
    const strip = axis === "column" ? this.columnStripTarget : this.rowStripTarget
    const template = axis === "column" ? this.columnTemplateTarget : this.rowTemplateTarget
    const text = messages(this.element)
    while (strip.children.length > count) strip.lastElementChild.remove()
    while (strip.children.length < count) {
      const index = strip.children.length
      const entry = template.content.firstElementChild.cloneNode(true)
      const button = entry.querySelector("[data-admin--ui--menu-target='button']")
      const columns = axis === "column"
      const name = columns ? columnLetter(index) : String(index + 1)
      entry.dataset[columns ? "tableColumn" : "tableRow"] = String(index)
      button.textContent = name
      const label = columns
        ? text.t("components.editor_screen.table_controls.column.menu", { letter: name })
        : text.t("components.editor_screen.table_controls.row.menu", { number: name })
      button.setAttribute("aria-label", label)
      button.setAttribute("tabindex", "-1")
      strip.append(entry)
    }
  }

  // Puts the strips on the grid's edges: a letter above each column, as wide
  // as its cell and cut at the scrolling box's edges, a number left of each
  // row, as tall as it, the corner where the two meet, the column's "+" after
  // the last letter and the row's "+" under the last number. The sizes of the
  // corner and of the "+" are the stylesheet's; this measures and places.
  //
  // IT RUNS ON EVERY KEYSTROKE (through `schedule`, once a frame) and a table
  // may have 500 rows, so it does as little as the change asks: every box is
  // READ first and every style WRITTEN after (one layout, not one per row);
  // the entries are added or removed only when the shape changed, the menus
  // refreshed only when the shape or an alignment did, and the entries
  // placed only when a measured box moved (the table's, the scrolling box's,
  // this element's, its scroll). Typing that wraps no line moves no box, so
  // it writes nothing but the current cell's marks. A row can only grow or
  // shrink by moving the table's bottom edge, so the table's box stands for
  // every row's.
  place() {
    const editor = this.usable()
    const box = this.wrapperElement()
    const table = box?.querySelector("table")
    const doc = editor?.state.doc
    const { rows, columns } = doc ? gridShape(doc) : { rows: 0, columns: 0 }
    if (!editor || !table || rows === 0 || table.rows.length !== rows) return this.hideStrips()

    const shape = `${rows}x${columns}`
    if (shape !== this.drawn.shape) {
      this.syncEntries("column", columns)
      this.syncEntries("row", rows)
      this.drawn.shape = shape
      this.drawn.geometry = null
    }
    // Shown before it is measured: a hidden corner has no size.
    this.cornerTarget.hidden = false

    // --- Read ---
    const base = this.element.getBoundingClientRect()
    const visible = box.getBoundingClientRect()
    const edges = table.getBoundingClientRect()
    // Relative to this element: the page scrolling moves everything together and is no change.
    const geometry = [ base.width, visible.left - base.left, visible.width, edges.left - base.left, edges.top - base.top, edges.width, edges.height, box.scrollLeft ].join(",")
    const menus = `${shape}:${Array.from({ length: columns }, (_, column) => columnAlign(doc, column)).join(",")}`

    if (geometry !== this.drawn.geometry) {
      const stripWidth = this.cornerTarget.offsetWidth
      const stripHeight = this.cornerTarget.offsetHeight
      const firstRow = table.rows[0].cells
      const letters = this.entries("column").map((_, index) => firstRow[index]?.getBoundingClientRect() || null)
      const numbers = Array.from(table.rows, (row) => row.getBoundingClientRect())
      const left = Math.max(edges.left, visible.left)
      const right = Math.min(edges.right, visible.right)
      const top = edges.top - stripHeight

      // --- Write ---
      this.entries("column").forEach((entry, index) => {
        const cell = letters[index]
        const from = cell ? Math.max(cell.left, left) : 0
        const to = cell ? Math.min(cell.right, right) : 0
        // The next letter's border is drawn over this one's (one line between two).
        this.put(entry, from - base.left, top - base.top, to - from + 1, stripHeight, to - from >= 1)
      })
      this.entries("row").forEach((entry, index) => {
        const row = numbers[index]
        this.put(entry, left - stripWidth - base.left, row.top - base.top, stripWidth, row.height + 1, true)
      })
      this.put(this.cornerTarget, left - stripWidth - base.left, top - base.top, null, null, true)
      this.put(this.addColumnTarget, right - base.left, top - base.top, null, null, true)
      this.put(this.addRowHereTarget, left - stripWidth - base.left, edges.bottom - base.top, null, null, true)
      this.columnStripTarget.hidden = false
      this.rowStripTarget.hidden = false
      this.drawn.geometry = geometry
    }

    this.markCurrent()
    // Not while a menu is open: its item's own click is still on its way to
    // the menu, which closes only for an item that is not disabled, and the
    // change it made could disable it (Move up on the row that is now the
    // first). `settle` makes them right once the menu has closed, since what
    // they were drawn for is then not remembered as drawn.
    if (menus !== this.drawn.menus && !this.menuOpen()) {
      this.refreshMenus(doc)
      this.drawn.menus = menus
    }
  }

  put(element, x, y, width, height, shown) {
    element.style.left = `${x}px`
    element.style.top = `${y}px`
    if (width !== null) element.style.width = `${width}px`
    if (height !== null) element.style.height = `${height}px`
    element.hidden = !shown
  }

  // The current cell's letter and number inverted and marked, and each
  // strip's ONE Tab stop: the button that has the focus, else the current
  // one while it is shown, else the first one shown (a letter whose column
  // is scrolled out is hidden, and a strip whose only stop is hidden is
  // skipped by Tab). Only the buttons that change are written: this runs on
  // every keystroke.
  markCurrent() {
    [ "column", "row" ].forEach((axis) => {
      const buttons = this.entries(axis).map((entry) => entry.querySelector(".admin-table-strip-button"))
      const index = this.current?.[axis]
      const current = index === undefined ? null : buttons[index] || null
      if (this.marked[axis] !== current) {
        this.marked[axis]?.removeAttribute("aria-current")
        current?.setAttribute("aria-current", "true")
        this.marked[axis] = current
      }

      const shown = (button) => Boolean(button) && !button.closest(".admin-table-strip-entry").hidden
      const focused = buttons.includes(document.activeElement) ? document.activeElement : null
      const stop = focused || (shown(current) ? current : buttons.find(shown)) || buttons[0] || null
      const previous = this.stops[axis]
      if (previous === stop && stop?.getAttribute("tabindex") === "0") return
      if (previous?.isConnected) previous.setAttribute("tabindex", "-1")
      stop?.setAttribute("tabindex", "0")
      this.stops[axis] = stop
    })
  }

  // What each item can do for its own row or column: a first row cannot move
  // up, a table's one row cannot be deleted (a grid is emptied by selecting
  // its cells, as any text is). The column's alignment is checked, as a radio
  // item (`menuitemradio`, set here after the menu has made every item a
  // `menuitem`).
  refreshMenus(doc) {
    const { rows, columns } = gridShape(doc)
    this.entries("row").forEach((entry, row) => {
      this.disable(entry, { move_up: row === 0, move_down: row === rows - 1, delete_row: rows === 1 })
    })
    this.entries("column").forEach((entry, column) => {
      this.disable(entry, { move_left: column === 0, move_right: column === columns - 1, delete_column: columns === 1 })
      const align = columnAlign(doc, column)
      entry.querySelectorAll("[data-table-align]").forEach((item) => {
        item.setAttribute("role", "menuitemradio")
        item.setAttribute("aria-checked", item.dataset.tableAlign === align ? "true" : "false")
      })
    })
  }

  disable(entry, off) {
    entry.querySelectorAll("[data-table-command]").forEach((item) => {
      item.disabled = Boolean(off[item.dataset.tableCommand])
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

  insertRowAbove(event) { this.structural(addRowBefore, ({ row, column }) => ({ row, column }), this.cellOf(event)) }
  insertRowBelow(event) { this.structural(addRowAfter, ({ row, column }) => ({ row: row + 1, column }), this.cellOf(event)) }
  moveRowUp(event) { this.move("row", -1, this.cellOf(event)) }
  moveRowDown(event) { this.move("row", 1, this.cellOf(event)) }
  insertColumnLeft(event) { this.structural(addColumnBefore, ({ row, column }) => ({ row, column }), this.cellOf(event)) }
  insertColumnRight(event) { this.structural(addColumnAfter, ({ row, column }) => ({ row, column: column + 1 }), this.cellOf(event)) }
  moveColumnLeft(event) { this.move("column", -1, this.cellOf(event)) }
  moveColumnRight(event) { this.move("column", 1, this.cellOf(event)) }

  // The "+" after the letters: a column after the last. The "+" under the
  // numbers and "Add row": a row after the last; into a grid emptied of its
  // table, the starting grid again.
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

  move(axis, step, cell) {
    if (!cell) return
    const from = cell[axis]
    const command = axis === "row" ? moveTableRow : moveTableColumn
    this.structural(command({ from, to: from + step, select: false }), (at) => ({ ...at, [axis]: from + step }), cell)
  }

  deleteRow(event) {
    const editor = this.usable()
    const cell = this.cellOf(event)
    if (!editor || !cell) return
    const { row, column } = cell
    const remove = () => this.structural(deleteRow, () => ({ row, column }), { row, column })
    rowHasText(editor.state.doc, row) ? this.confirm(this.rowDialogValue, remove, { row, column }) : remove()
  }

  deleteColumn(event) {
    const editor = this.usable()
    const cell = this.cellOf(event)
    if (!editor || !cell) return
    const { row, column } = cell
    const remove = () => this.structural(deleteColumn, () => ({ row, column }), { row, column })
    columnHasText(editor.state.doc, column) ? this.confirm(this.columnDialogValue, remove, { row, column }) : remove()
  }

  // Align: Left, Centre, Right, for every cell of the menu's column.
  align(event) {
    const editor = this.usable()
    const cell = this.cellOf(event)
    if (!editor || !cell) return
    const { row, column } = cell
    const at = insideCell(editor.state.doc, row, column)
    if (at === null) return
    this.current = cell
    editor.chain().focus().setTextSelection(at).command(({ tr }) => {
      alignColumn(tr, column, event.params.align)
      return true
    }).run()
  }

  // One transaction: the caret into `cell`, the prosemirror-tables command,
  // which acts on the selection's cell, the header kinds as the switches said
  // before (see the top of this file), and the caret into the cell `after`
  // names in the new shape. `focus()` comes first in the chain: with no
  // position it puts back the selection the editor had, so anywhere later it
  // would undo the selection set here.
  structural(command, after, cell) {
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

// A column's letter as a spreadsheet writes it: A to Z, then AA, AB, … (a
// table has at most 30 columns, `TableBody::MAX_COLUMNS`).
function columnLetter(index) {
  let letters = ""
  for (let n = index + 1; n > 0; n = Math.floor((n - 1) / 26)) letters = String.fromCharCode(65 + ((n - 1) % 26)) + letters
  return letters
}
