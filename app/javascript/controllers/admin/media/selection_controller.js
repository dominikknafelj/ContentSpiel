import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// The Media screen's selection mode (`select=1`, the card StudioMediaFolders,
// D6), on `#media-library`, which holds both the bar
// (`Admin::MediaLibrary::SelectionBarComponent`) and the grid.
//
// THE SELECTION IS THIS PAGE'S. The server draws every tile as a button with
// `aria-pressed="false"` and its tick unticked (`TileComponent`, `select:
// true`); which of them are ticked lives here alone, so a visit (a place, a
// page, a search, Done, Back) leaves it with the page, and a page Turbo draws
// again starts empty. Nothing is written to the address or to storage.
//
// THE TILES. A press toggles one (Space and Enter are the button's own
// press), and remembers it as the anchor; Shift+click ticks every tile from
// the anchor to the one pressed, in grid order (the document's order, which is
// the grid's), and makes it the anchor. A tile's state is its `aria-pressed`,
// which the stylesheet draws as the accent outline (`.admin-tile`), and the
// tick in its chip follows it. A tile that leaves the page (a move's answer
// takes the moved tiles out of a folder's grid) leaves the selection and the
// count Select all says.
//
// THE BAR. "N selected" and the status beside the bar say the count (the
// status only on a change, so a screen reader hears what a press did);
// "Select all N" ticks every tile the page draws and reads "All N selected"
// while they all are (`aria-disabled` then, keeping the focus where it is);
// Clear unticks them all. Move to… is disabled with nothing ticked, and its
// params (drawn by `MoveDialogComponent.images_trigger`) are rewritten with
// the ticked ids and, for one, its title, as the selection changes, so the
// dialog opens on exactly what is ticked.
//
// AFTER A MOVE. A move the dialog sent that succeeded (`turbo:submit-end` of
// its form, `media-move-form`) unticks the images it moved: they leave a
// folder's grid, and in All media they stay drawn, unticked. When the dialog
// then closes onto a Move to… that the emptied selection disabled, the focus
// would fall to <body>; it goes to Select all instead.
//
// TURBO'S SNAPSHOT. Whatever this writes into the tiles and the bar (the
// pressed state, the ticks, Move to…'s params) is taken back before Turbo
// caches the page, so Back to a `select=1` entry starts with nothing ticked.
//
// LEAVING. Done is a content-frame link to the place without `select`; Escape
// presses it, unless something on the page takes Escape first (an open
// dialog or menu, a field: their keydown happens inside them, and a dialog's
// own Escape closes the dialog).
const PARAM = "data-admin--media--move-"
const MOVE_FORM = "media-move-form"

export default class extends Controller {
  static targets = ["tile", "count", "status", "selectAll", "move", "done"]

  connect() {
    this.anchor = null
    this.announced = 0
    this.handlers = {
      "turbo:before-cache": () => this.reset(),
      "turbo:submit-end": (event) => this.moved(event),
      "admin--ui--dialog:opening": (event) => this.opening(event)
    }
    Object.entries(this.handlers).forEach(([name, handler]) => document.addEventListener(name, handler))
    this.sync()
  }

  disconnect() {
    Object.entries(this.handlers).forEach(([name, handler]) => document.removeEventListener(name, handler))
  }

  toggle(event) {
    const tile = event.currentTarget
    const tiles = this.tileTargets
    if (event.shiftKey && this.anchor && tiles.includes(this.anchor)) {
      const [from, to] = [tiles.indexOf(this.anchor), tiles.indexOf(tile)].sort((a, b) => a - b)
      tiles.slice(from, to + 1).forEach((each) => this.press(each, true))
    } else {
      this.press(tile, !this.pressed(tile))
    }
    this.anchor = tile
    this.sync()
  }

  selectAll() {
    if (this.hasSelectAllTarget && this.selectAllTarget.getAttribute("aria-disabled") === "true") return
    this.tileTargets.forEach((tile) => this.press(tile, true))
    this.sync()
  }

  clear() {
    this.tileTargets.forEach((tile) => this.press(tile, false))
    this.anchor = null
    this.sync()
  }

  escape(event) {
    if (event.defaultPrevented || !this.hasDoneTarget) return
    const target = event.target
    if (target instanceof Element && target.closest("dialog, [role=menu], input, textarea, select, [contenteditable]")) return
    if (document.querySelector("dialog[open]")) return

    this.doneTarget.click()
  }

  // Also called for every tile as the page itself goes, when there is
  // nothing left to say.
  tileTargetDisconnected(tile) {
    if (this.anchor === tile) this.anchor = null
    if (this.element.isConnected) this.sync()
  }

  // private

  reset() {
    this.tileTargets.forEach((tile) => this.press(tile, false))
    this.anchor = null
    this.sync()
    if (this.hasStatusTarget) this.statusTarget.textContent = ""
    this.announced = 0
  }

  moved(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement) || form.id !== MOVE_FORM || !event.detail?.success) return

    const ids = new Set(Array.from(form.querySelectorAll("input[name='asset_ids[]']"), (input) => input.value))
    this.tileTargets.forEach((tile) => { if (ids.has(tile.dataset.assetId)) this.press(tile, false) })
    this.sync()
  }

  // The dialog opened from Move to…: when it closes, a focus left on
  // nothing, or on the disabled Move to…, goes to Select all. Checked a frame
  // after `close`, once the browser has put the focus where it puts it.
  opening(event) {
    const { dialog, trigger } = event.detail || {}
    if (!dialog || !this.hasMoveTarget || trigger !== this.moveTarget) return

    dialog.addEventListener("close", () => requestAnimationFrame(() => {
      const active = document.activeElement
      const lost = !active || active === document.body || active === this.moveTarget || active.getClientRects().length === 0
      if (lost && this.moveTarget.disabled && this.hasSelectAllTarget) this.selectAllTarget.focus()
    }), { once: true })
  }

  pressed(tile) {
    return tile.getAttribute("aria-pressed") === "true"
  }

  press(tile, on) {
    tile.setAttribute("aria-pressed", on ? "true" : "false")
    const tick = tile.querySelector("[data-media-tick] input[type=checkbox]")
    if (tick) tick.checked = on
  }

  // The bar's words are on the bar (`data-messages`), which the count is in.
  sync() {
    if (!this.hasCountTarget) return

    const tiles = this.tileTargets
    const ticked = tiles.filter((tile) => this.pressed(tile))
    const words = messages(this.countTarget)
    const count = words.t("components.media_library.selection.count", { count: ticked.length })

    this.countTarget.textContent = count
    if (this.hasSelectAllTarget) {
      const all = tiles.length > 0 && ticked.length === tiles.length
      this.selectAllTarget.textContent = words.t(
        all ? "components.media_library.selection.all_selected" : "components.media_library.selection.select_all",
        { count: tiles.length }
      )
      if (all) this.selectAllTarget.setAttribute("aria-disabled", "true")
      else this.selectAllTarget.removeAttribute("aria-disabled")
    }
    if (this.hasMoveTarget) {
      this.moveTarget.disabled = ticked.length === 0
      this.moveTarget.setAttribute(`${PARAM}asset-ids-param`, ticked.map((tile) => tile.dataset.assetId).join(","))
      this.moveTarget.setAttribute(`${PARAM}title-param`, ticked.length === 1 ? ticked[0].dataset.assetTitle || "" : "")
    }
    if (this.hasStatusTarget && ticked.length !== this.announced) {
      this.statusTarget.textContent = count
      this.announced = ticked.length
    }
  }
}
