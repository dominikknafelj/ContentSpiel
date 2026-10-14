import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// The page tree's divider (`Admin::Shell::TreeDividerComponent`; Claude
// Design, 2026-10-13, T1 and T3): the tree column is as wide as the person
// made it, between a minimum and a maximum, and the choice is remembered in
// this browser.
//
// WHERE THE WIDTH LIVES. One custom property on <html>,
// `--admin-tree-width`, in pixels: the CHOSEN width. The shell's grid reads
// it (content-spiel.tailwind.css, `--admin-tree-column`; 17rem without it),
// so a drag is nothing but writing that property again, and the editor beside
// the tree reflows by itself. It is on <html> because Turbo replaces <body>
// and merges <head> and never touches the root element: a visit to another
// screen, a page picked in the tree and Back all find the width where it was,
// with nothing to restore and nothing in a snapshot to go stale. The layout's
// head script (`admin/shared/_tree_head`) puts it there from `localStorage`
// before the first paint; this controller never reads the storage itself, so
// the page cannot change width when it connects. It only writes there what
// the person chose (guarded: a browser that refuses storage keeps the choice
// for as long as the document lives, and starts at the default again).
//
// CHOSEN AND SHOWN are two numbers. On a window too narrow for the choice the
// grid shows less (the stylesheet clamps the track so the editor keeps its
// 640px), and the choice is kept for when there is room again; `width` is
// what is shown, and what the separator says as its value and the arrow keys
// step from. `ceiling` is the widest the column may be right now: the
// maximum, or less where sidebar + tree + editor's 640px (+ the notes
// column's 400px while it stands beside the editor) would not fit the window.
// The window's width is `innerWidth`, which is what a media query and `100vw`
// measure, so this arithmetic and the stylesheet's agree to the pixel.
//
// BESIDE THE NOTES (T3). `data-tree-fits` on <html> says whether the tree AT
// ITS CHOSEN WIDTH still fits beside the notes column with 640px left for the
// editor. The stylesheet folds the tree into its drawer while the notes are
// open and that attribute is absent ("THE PAGE TREE FOLDS"), since no media
// query can read the property. It is said whether or not the notes are open
// (the stylesheet asks it only then), kept current here on a resize and on
// every change of the width, and by the head script before the first paint.
// Studio never narrows the tree to make it fit: it folds, and the column is
// back at the same width when the notes close. While the notes are open and
// the tree is a column, the divider stops at the width that still fits, so a
// drag never folds the tree under the pointer that drags it.
//
// THE POINTER. A press on the divider begins a drag, and from then until the
// release (or a cancelled pointer) the pointer is listened for on the WINDOW:
// it is over the editor or the tree most of the time, not over an 8px strip.
// Listeners on the window and not `setPointerCapture`: a capture is kept only
// while the browser believes a button is down, and a pointer driven through
// the DevTools protocol (the system tests') reports none while it moves, so
// the capture was dropped without a word and the drag went nowhere; the
// window's listeners work for both. <html> carries `data-tree-resizing` for
// as long (no text is selected on the way, the cursor stays `col-resize`
// wherever the pointer is) and the divider `data-dragging` (its accent
// line). A double click resets to the default.
// The line under a resting pointer and its cursor come 150ms after the
// pointer arrived (`data-hover`), so a pointer that only passes over on its
// way from the tree to the editor makes nothing flicker.
//
// THE KEYBOARD (ARIA's window splitter). Left and Right step 16px, with
// Shift 64px; Home and End go to the minimum and to the widest that fits;
// Enter resets. Every other key, and every chord with Alt, Ctrl or Meta, is
// left to the browser.
//
// WHAT IS TAKEN BACK. The two attributes on the divider and the one on <html>
// that say "a pointer is at work" go when the pointer does, and again in
// `rest` (before Turbo copies the page) and on disconnect, so no snapshot and
// no next screen is left in the middle of a drag. The width and
// `data-tree-fits` are NOT taken back: they are the state of the document,
// not of this element. What the separator says of itself (its three values,
// the tooltip's sentence) is written again on connect, so a copy that Turbo
// kept from before a resize is right as soon as it is shown.
const PROPERTY = "--admin-tree-width"
const FITS = "data-tree-fits"
const RESIZING = "data-tree-resizing"
const HOVER_DELAY = 150
const STEP = 16
const STRIDE = 64

export default class extends Controller {
  static values = { min: Number, default: Number, max: Number, editor: Number, sidebar: Number, notes: Number, key: String }

  connect() {
    this.pointer = null
    this.moved = (event) => this.drag(event)
    this.released = (event) => this.release(event)
    // The notes drawer opening or closing changes how far the divider may go.
    // It says so on <html> (`data-notes-open`); nothing is dispatched when it
    // closes, so the attribute is watched.
    this.observer = new MutationObserver(() => this.sync())
    this.observer.observe(this.root, { attributes: true, attributeFilter: [ "data-notes-open" ] })
    this.sync()
  }

  disconnect() {
    this.observer?.disconnect()
    this.observer = null
    this.rest()
  }

  // --- the pointer ------------------------------------------------------------

  press(event) {
    if (event.button !== 0 || this.pointer) return

    // No text selection begins under a drag, and no drag of an image.
    event.preventDefault()
    this.pointer = { id: event.pointerId, from: event.clientX, width: this.width, moved: false }
    window.addEventListener("pointermove", this.moved)
    window.addEventListener("pointerup", this.released)
    window.addEventListener("pointercancel", this.released)
    this.element.setAttribute("data-dragging", "")
    this.root.setAttribute(RESIZING, "")
  }

  drag(event) {
    if (!this.pointer || event.pointerId !== this.pointer.id) return

    this.pointer.moved = true
    this.apply(this.pointer.width + event.clientX - this.pointer.from)
  }

  // `pointerup` and `pointercancel`. A press that never moved chose nothing
  // (it may be the first half of a double click).
  release(event) {
    if (!this.pointer || event.pointerId !== this.pointer.id) return

    const moved = this.pointer.moved
    this.settle()
    if (moved) this.remember()
  }

  enter(event) {
    if (event.pointerType === "touch") return
    clearTimeout(this.hovering)
    this.hovering = setTimeout(() => this.element.setAttribute("data-hover", ""), HOVER_DELAY)
  }

  leave() {
    clearTimeout(this.hovering)
    this.element.removeAttribute("data-hover")
  }

  // --- the keyboard -----------------------------------------------------------

  key(event) {
    if (event.altKey || event.ctrlKey || event.metaKey) return

    const step = event.shiftKey ? STRIDE : STEP
    if (event.key === "ArrowLeft") this.choose(this.width - step)
    else if (event.key === "ArrowRight") this.choose(this.width + step)
    else if (event.key === "Home") this.choose(this.minValue)
    else if (event.key === "End") this.choose(this.ceiling)
    else if (event.key === "Enter") this.reset()
    else return

    // The arrows and Home / End would scroll the page.
    event.preventDefault()
  }

  // --- the width --------------------------------------------------------------

  // The default again (a double click, Enter): the property and the stored
  // choice both go, so the stylesheet's own 17rem is what draws the column.
  // Where the default does not fit just now (a narrow window with the notes
  // beside the editor), the widest that does: a reset must not fold the tree
  // under the person any more than a drag may.
  reset() {
    if (this.defaultValue > this.ceiling) return this.choose(this.ceiling)

    this.root.style.removeProperty(PROPERTY)
    try {
      window.localStorage.removeItem(this.keyValue)
    } catch {
      // A convenience only.
    }
    this.sync()
  }

  choose(width) {
    this.apply(width)
    this.remember()
  }

  // Whole pixels, between the minimum and what fits right now.
  apply(width) {
    const next = Math.round(Math.min(Math.max(width, this.minValue), this.ceiling))
    this.root.style.setProperty(PROPERTY, `${next}px`)
    this.sync()
  }

  remember() {
    try {
      window.localStorage.setItem(this.keyValue, String(this.chosen))
    } catch {
      // A convenience only: the property on <html> holds the choice for as
      // long as this document lives.
    }
  }

  // Everything that follows from the width, the window and the notes drawer,
  // said again: whether the tree fits beside the notes (for the stylesheet),
  // and what the separator tells a screen reader and its tooltip. Called on
  // connect, on every change of the width, on `resize`, when the notes open
  // or close, when a frame has loaded (an editor with a drawer may have
  // arrived in `#content`) and when the divider takes the focus.
  sync() {
    const room = this.sidebar + this.chosen + this.notesValue + this.editorValue
    this.root.toggleAttribute(FITS, window.innerWidth >= room)

    const width = this.width
    this.element.setAttribute("aria-valuemin", String(this.minValue))
    this.element.setAttribute("aria-valuemax", String(this.ceiling))
    this.element.setAttribute("aria-valuenow", String(width))
    const bubble = this.element.querySelector("[data-tooltip]")
    if (bubble) bubble.textContent = messages(this.element).t("components.shell.tree_divider.tooltip", { width })
  }

  // `turbo:before-cache`, and on disconnect: no pointer is at work in a page
  // that is put away.
  rest() {
    this.leave()
    this.settle()
  }

  // The end of a drag, or none to end: the window's listeners and the two
  // marks go together.
  settle() {
    this.pointer = null
    window.removeEventListener("pointermove", this.moved)
    window.removeEventListener("pointerup", this.released)
    window.removeEventListener("pointercancel", this.released)
    this.element.removeAttribute("data-dragging")
    this.root.removeAttribute(RESIZING)
  }

  get root() { return document.documentElement }

  // What the person chose: the property, or the default while there is none.
  get chosen() {
    const value = parseFloat(this.root.style.getPropertyValue(PROPERTY))
    return Number.isFinite(value) ? value : this.defaultValue
  }

  // What the grid shows: the choice, held between the minimum and what fits.
  get width() {
    return Math.round(Math.min(Math.max(this.chosen, this.minValue), this.ceiling))
  }

  // The widest the column may be now, never under the minimum: the editor
  // keeps its 640px beside the sidebar (where that is a column) and beside
  // the notes (while they are).
  get ceiling() {
    const room = window.innerWidth - this.sidebar - this.editorValue - (this.notesBeside ? this.notesValue : 0)
    return Math.max(this.minValue, Math.min(this.maxValue, Math.floor(room)))
  }

  // The modules sidebar is a column of the grid from 1280px and a drawer
  // below (`.admin-shell` in the stylesheet).
  get sidebar() {
    return window.matchMedia("(min-width: 1280px)").matches ? this.sidebarValue : 0
  }

  // The notes as a column beside the editor: exactly what the stylesheet
  // asks (`:root[data-notes-open] body:has(#notes-drawer)`, from 1024px,
  // below which this divider is not shown at all).
  get notesBeside() {
    return this.root.hasAttribute("data-notes-open") && document.getElementById("notes-drawer") !== null
  }
}
