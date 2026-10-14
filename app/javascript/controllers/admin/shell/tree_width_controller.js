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
// ONE UNIT: THE STYLESHEET'S. The shell is laid out in rem (the sidebar is
// 15rem, the tree 17rem until someone chooses, its limits 13.75rem and
// 30rem, the editor's least 40rem), and the design's figures -- 240, 272,
// 220, 480, 640 -- are those at a root font size of 16px. A person whose
// browser is set to 20px has a 340px tree beside a 300px sidebar. So the
// values this controller is handed are the figures at 16px, and every one is
// multiplied by `scale` (the root's computed font size over 16) before it is
// used: `least`, `most`, `standard`, `editor`, `sidebar`, and the keys'
// steps. The one exception is the notes column, which the stylesheet makes
// 400px at any font size (`--admin-notes-width`), and so does this. What is
// written (the property, the storage) and what is said (`aria-valuenow`, the
// tooltip) are CSS pixels of the real column. The first build counted 272
// and 240 as pixels: at 20px the separator said 272 for a 340px column, the
// first arrow key made it 52px narrower on "wider", a drag began with a
// jump, and the tree was said to fit beside the notes 128px too early
// (`test/system/admin/tree_column_test.rb`: "at a browser font size of 20px…").
//
// CHOSEN AND SHOWN are two numbers. On a window too narrow for the choice the
// grid shows less (the stylesheet clamps the track so the editor keeps its
// 40rem), and the choice is kept for when there is room again; `width` is
// what is shown, and what the separator says as its value and the arrow keys
// step from. `ceiling` is the widest the column may be right now: the
// maximum, or less where sidebar + tree + the editor's least (+ the notes
// column while it stands beside the editor) would not fit the window. A key
// that asks for more than the ceiling while the choice is already wider than
// what is shown writes nothing: it moved nothing, and must not throw away the
// wider choice. The window's width is `innerWidth`, which is what a media
// query and `100vw` measure, and the lengths are the stylesheet's own in its
// own unit, so this arithmetic and the stylesheet's agree at any font size
// (to the rounding of a whole pixel where a rem figure is not one).
//
// BESIDE THE NOTES (T3). `data-tree-fits` on <html> says whether the tree AT
// ITS CHOSEN WIDTH still fits beside the notes column with the editor's
// least left. The stylesheet folds the tree into its drawer while the notes
// are open and that attribute is absent ("THE PAGE TREE STAYS BESIDE THE
// EDITOR WHILE IT FITS, AND FOLDS WHEN IT DOES NOT"), since no media query
// can read the property. It is said whether or not the notes are open (the
// stylesheet asks it only then), kept current here on a resize and on every
// change of the width, and by the head script before the first paint.
// Studio never narrows the tree to make it fit: it folds, and the column is
// back at the same width when the notes close. While the notes are open and
// the tree is a column, the divider stops at the width that still fits, so a
// drag never folds the tree under the pointer that drags it. A RESET is the
// one thing that may: Enter and a double click ask for the default, and
// where the default does not fit beside the notes the tree folds, like any
// other width that does not fit.
//
// THE POINTER. A press with the primary button begins a drag, and from then
// until its end the pointer is listened for on the WINDOW (`pointermove`,
// `pointerup`, `pointercancel`, added at the press and removed at the end):
// it is over the editor or the tree most of the time, not over an 8px strip.
// The press also CAPTURES the pointer (`setPointerCapture`), which is what
// keeps the moves coming while the pointer is outside the window and tells
// this element when the browser takes the pointer away
// (`lostpointercapture`). The capture is an addition and not the mechanism,
// because it can be dropped without a word: measured on 2026-10-13, Chrome
// lets go of a capture on a mouse move that names `buttons` but no `button`
// and fires no `lostpointercapture` -- which is every move Ferrum's
// `mouse.move` sends (0.18.0), so a drag that relied on the capture alone
// went nowhere in a system test. A captured pointer's events are targeted at
// this element and bubble to the window, so the window's listeners hear a
// drag with the capture and without it. <html> carries `data-tree-resizing`
// for as long (no text is selected on the way, the cursor stays `col-resize`
// wherever the pointer is) and the divider `data-dragging` (its accent line).
// A DRAG ALWAYS HAS AN END, also where the release never arrives:
// - a move of a mouse that reports no button down (`buttons === 0`: the
//   button was let go where this page did not hear it) ends it as a release
//   would, keeping the width;
// - the window losing the focus (`blur`: Cmd-Tab mid-drag) and a lost
//   capture end it the same way;
// - `pointercancel` is the system taking the pointer away, not the person
//   choosing: the width goes back to what it was at the press, and nothing
//   is stored;
// - a press with Ctrl is not a press: on macOS it opens the context menu,
//   which swallows the release.
// A double click resets to the default.
// The line under a resting pointer and its cursor come 150ms after the
// pointer arrived (`data-hover`), so a pointer that only passes over on its
// way from the tree to the editor makes nothing flicker.
//
// THE KEYBOARD (ARIA's window splitter). Left and Right step 1rem (16px),
// with Shift 4rem (64px); Home and End go to the minimum and to the widest
// that fits; Enter resets. Every other key, and every chord with Alt, Ctrl
// or Meta, is left to the browser.
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
// The font size the handed figures are for, and the keys' steps at it.
const BASE = 16
const STEP = 16
const STRIDE = 64

export default class extends Controller {
  static values = { min: Number, default: Number, max: Number, editor: Number, sidebar: Number, notes: Number, key: String }

  connect() {
    this.pointer = null
    this.moved = (event) => this.drag(event)
    this.released = (event) => this.release(event)
    this.cancelled = (event) => this.cancel(event)
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
    // The primary button only, and not with Ctrl (the context menu on macOS).
    if (event.button !== 0 || event.ctrlKey || this.pointer) return

    // No text selection begins under a drag, and no drag of an image.
    event.preventDefault()
    this.pointer = { id: event.pointerId, from: event.clientX, width: this.width, chosen: this.root.style.getPropertyValue(PROPERTY), moved: false }
    window.addEventListener("pointermove", this.moved)
    window.addEventListener("pointerup", this.released)
    window.addEventListener("pointercancel", this.cancelled)
    try {
      this.element.setPointerCapture(event.pointerId)
    } catch {
      // A pointer that is already gone cannot be captured; the window's
      // listeners and `blur` still end what was begun.
    }
    this.element.setAttribute("data-dragging", "")
    this.root.setAttribute(RESIZING, "")
  }

  drag(event) {
    if (!this.pointer || event.pointerId !== this.pointer.id) return
    // The button was let go where this page did not hear it.
    if (event.pointerType === "mouse" && event.buttons === 0) return this.release(event)

    this.pointer.moved = true
    this.apply(this.pointer.width + event.clientX - this.pointer.from)
  }

  // `pointerup` on the window, `lostpointercapture` (whichever comes first;
  // the other finds no drag), a mouse's move with no button, and the
  // window's `blur`.
  // A press that never moved chose nothing (it may be the first half of a
  // double click).
  release(event) {
    if (!this.pointer || (event?.pointerId !== undefined && event.pointerId !== this.pointer.id)) return

    const moved = this.pointer.moved
    this.settle()
    if (moved) this.remember()
  }

  // `pointercancel`: the width as it was at the press, and nothing stored.
  cancel(event) {
    if (!this.pointer || event.pointerId !== this.pointer.id) return

    const before = this.pointer.chosen
    this.settle()
    if (before) this.root.style.setProperty(PROPERTY, before)
    else this.root.style.removeProperty(PROPERTY)
    this.sync()
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

    const step = (event.shiftKey ? STRIDE : STEP) * this.scale
    if (event.key === "ArrowLeft") this.choose(this.width - step)
    else if (event.key === "ArrowRight") this.choose(this.width + step)
    else if (event.key === "Home") this.choose(this.least)
    else if (event.key === "End") this.choose(this.ceiling)
    else if (event.key === "Enter") this.reset()
    else return

    // The arrows and Home / End would scroll the page.
    event.preventDefault()
  }

  // --- the width --------------------------------------------------------------

  // The default again (a double click, Enter): the property and the stored
  // choice both go, so the stylesheet's own 17rem is what draws the column,
  // at any font size, and "the default" is what is remembered. Where the
  // default does not fit beside the open notes the tree folds, as it does for
  // any other width that does not fit: Studio never narrows the tree itself,
  // and a person who asked for the default gets the default.
  reset() {
    this.root.style.removeProperty(PROPERTY)
    try {
      window.localStorage.removeItem(this.keyValue)
    } catch {
      // A convenience only.
    }
    this.sync()
  }

  // A key's choice. One that would only be cut back to what is already shown
  // (Right or End at a window-clamped width) while the choice is wider is
  // nothing: the wider choice is kept for a wider window.
  choose(width) {
    const next = this.held(width)
    if (next === this.width && this.chosen > next) return

    this.apply(width)
    this.remember()
  }

  apply(width) {
    this.root.style.setProperty(PROPERTY, `${this.held(width)}px`)
    this.sync()
  }

  // Whole pixels, between the minimum and what fits right now (the two
  // limits themselves may be a fraction where a rem is not a whole pixel).
  held(width) {
    return Math.min(Math.max(Math.round(width), this.least), this.ceiling)
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
    const room = this.sidebar + this.chosen + this.notesValue + this.editor
    this.root.toggleAttribute(FITS, window.innerWidth >= room)

    const width = Math.round(this.width)
    this.element.setAttribute("aria-valuemin", String(Math.round(this.least)))
    this.element.setAttribute("aria-valuemax", String(Math.round(this.ceiling)))
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

  // The end of a drag, or none to end: the window's listeners, the capture
  // and the two marks go together.
  settle() {
    const pointer = this.pointer
    this.pointer = null
    window.removeEventListener("pointermove", this.moved)
    window.removeEventListener("pointerup", this.released)
    window.removeEventListener("pointercancel", this.cancelled)
    this.element.removeAttribute("data-dragging")
    this.root.removeAttribute(RESIZING)
    if (!pointer) return
    try {
      this.element.releasePointerCapture(pointer.id)
    } catch {
      // Already gone (`lostpointercapture` is how this was reached).
    }
  }

  get root() { return document.documentElement }

  // The root's font size over the 16px the handed figures are for.
  get scale() {
    const size = parseFloat(window.getComputedStyle(this.root).fontSize)
    return Number.isFinite(size) && size > 0 ? size / BASE : 1
  }

  get least() { return this.minValue * this.scale }
  get most() { return this.maxValue * this.scale }
  get standard() { return this.defaultValue * this.scale }
  get editor() { return this.editorValue * this.scale }

  // What the person chose: the property, or the default while there is none.
  get chosen() {
    const value = parseFloat(this.root.style.getPropertyValue(PROPERTY))
    return Number.isFinite(value) ? value : this.standard
  }

  // What the grid shows: the choice, held between the minimum and what fits.
  get width() {
    return Math.min(Math.max(this.chosen, this.least), this.ceiling)
  }

  // The widest the column may be now, never under the minimum: the editor
  // keeps its least beside the sidebar (where that is a column) and beside
  // the notes (while they are).
  get ceiling() {
    const room = window.innerWidth - this.sidebar - this.editor - (this.notesBeside ? this.notesValue : 0)
    return Math.max(this.least, Math.min(this.most, Math.floor(room)))
  }

  // The modules sidebar is a column of the grid from 1280px and a drawer
  // below (`.admin-shell` in the stylesheet). The breakpoint is a media
  // query's, in pixels at any font size; the column is 15rem.
  get sidebar() {
    return window.matchMedia("(min-width: 1280px)").matches ? this.sidebarValue * this.scale : 0
  }

  // The notes as a column beside the editor: exactly what the stylesheet
  // asks (`:root[data-notes-open] body:has(#notes-drawer)`, from 1024px,
  // below which this divider is not shown at all).
  get notesBeside() {
    return this.root.hasAttribute("data-notes-open") && document.getElementById("notes-drawer") !== null
  }
}
