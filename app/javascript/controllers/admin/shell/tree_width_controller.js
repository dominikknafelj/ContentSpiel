import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// The tree column (`aside#tree-column`, with its data from
// `Admin::Shell::TreeDividerComponent.column_data`), whatever the screen
// puts in it (the Pages tree, the mind graph's list): the column is as wide
// as the person made it with
// its divider (the `divider` target), between a minimum and a maximum, it
// folds to a strip and back (the `fold` and `unfold` targets), and both
// choices are remembered in this browser.
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
// used: `least`, `most`, `standard`, `editor`, `sidebar` and the
// keys' steps. What is written (the property, the storage) and what is said
// (`aria-valuenow`, the tooltip) are CSS pixels of the real column. Counted
// as pixels, the figures go wrong at any other font size: at 20px the
// separator would say 272 for a 340px column, the first arrow key would make
// it 52px narrower on "wider", a drag would begin with a jump, and the tree
// would be allowed 80px more than the grid draws
// (`test/system/admin/tree_column_test.rb`: "at a browser font size of
// 20px…").
//
// CHOSEN AND SHOWN are two numbers. On a window too narrow for the choice the
// grid shows less (the stylesheet clamps the track so the editor keeps its
// 40rem), and the choice is kept for when there is room again; `width` is
// what is shown, and what the separator says as its value and the arrow keys
// step from. `ceiling` is the widest the column may be right now: the
// maximum, or less where sidebar + tree + the editor's least would not fit
// the window. A key
// that asks for more than the ceiling while the choice is already wider than
// what is shown writes nothing: it moved nothing, and must not throw away the
// wider choice. The window's width is the document's less its scrollbar's
// gutter, which CS Studio keeps (`windowWidth`: the root's box, what
// the stylesheet's `100%` of the shell is), and the lengths are the
// stylesheet's own in its own unit, so this arithmetic and the stylesheet's
// agree at any font size and with a classic scrollbar (to the rounding of a
// whole pixel where a rem figure is not one).
//
// THE FOLD, a third state of the width. The column head's hide button
// (`fold`, `Admin::Ui::TreeHideComponent`) and the strip's one button
// (`unfold`, `Admin::Shell::TreeFoldComponent`) set and take away `data-tree-folded` on
// <html>, and "1" under `foldKey` in `localStorage`. The attribute has two
// writers, as the width has: the layout's head script, before the first
// paint, and this controller. The stylesheet makes the grid's track the
// strip while it is there (`--admin-tree-column` is its own derived
// property; `--admin-tree-strip`), from 1024px only: below, the tree is a
// drawer and the fold means nothing. The CHOSEN width is untouched by a
// fold: `--admin-tree-width` keeps its one meaning, so an unfold reads
// nothing from the storage and the column comes back at it. Each press
// moves the focus to the other button, which is the one shown afterwards,
// and both say the column's state (`aria-expanded`, written in `sync`, and
// as a `fold` button arrives with a replaced tree).
//
// THE POINTER. A press with the primary button begins a drag, and from then
// until its end the pointer is listened for on the WINDOW (`pointermove`,
// `pointerup`, `pointercancel`, added at the press and removed at the end):
// it is over the editor or the tree most of the time, not over an 8px strip.
// The press also CAPTURES the pointer (`setPointerCapture`), which is what
// keeps the moves coming while the pointer is outside the window and tells
// the divider when the browser takes the pointer away
// (`lostpointercapture`). The capture is an addition and not the mechanism,
// because it can be dropped without a word: measured on 2026-10-13, Chrome
// lets go of a capture on a mouse move that names `buttons` but no `button`
// and fires no `lostpointercapture` -- which is every move Ferrum's
// `mouse.move` sends (0.18.0), so a drag that relied on the capture alone
// went nowhere in a system test. A captured pointer's events are targeted at
// the divider and bubble to the window, so the window's listeners hear a
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
// no next screen is left in the middle of a drag. The width, the fold and
// the two remembered keys are NOT taken back:
// they are the state of the document, not of this element. What the
// separator and the two buttons say of themselves (its three values, the
// tooltip's sentence, their `aria-expanded`) is written again on connect, so
// a copy that Turbo kept from before a resize or a fold is right as soon as
// it is shown.
const PROPERTY = "--admin-tree-width"
const FOLDED = "data-tree-folded"
const RESIZING = "data-tree-resizing"
const HOVER_DELAY = 150
// The font size the handed figures are for, and the keys' steps at it.
const BASE = 16
const STEP = 16
const STRIDE = 64

export default class extends Controller {
  static targets = ["divider", "fold", "unfold"]
  // `tooltipKey` is the message key of the divider's tooltip, in the words of
  // what the column holds (`Admin::Shell::TreeSubjects`); the divider's
  // `data-messages` carries that key's sentence.
  static values = { min: Number, default: Number, max: Number, editor: Number, sidebar: Number, key: String, foldKey: String, tooltipKey: String }

  connect() {
    this.pointer = null
    this.moved = (event) => this.drag(event)
    this.released = (event) => this.release(event)
    this.cancelled = (event) => this.cancel(event)
    this.sync()
  }

  disconnect() {
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
      this.dividerTarget.setPointerCapture(event.pointerId)
    } catch {
      // A pointer that is already gone cannot be captured; the window's
      // listeners and `blur` still end what was begun.
    }
    this.dividerTarget.setAttribute("data-dragging", "")
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
    this.hovering = setTimeout(() => this.dividerTarget.setAttribute("data-hover", ""), HOVER_DELAY)
  }

  leave() {
    clearTimeout(this.hovering)
    if (this.hasDividerTarget) this.dividerTarget.removeAttribute("data-hover")
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

  // --- the fold ---------------------------------------------------------------

  fold() {
    this.root.setAttribute(FOLDED, "")
    try {
      window.localStorage.setItem(this.foldKeyValue, "1")
    } catch {
      // A convenience only: the attribute holds the fold for as long as this
      // document lives.
    }
    this.sync()
    if (this.hasUnfoldTarget) this.unfoldTarget.focus()
  }

  unfold() {
    this.root.removeAttribute(FOLDED)
    try {
      window.localStorage.removeItem(this.foldKeyValue)
    } catch {
      // A convenience only.
    }
    this.sync()
    if (this.hasFoldTarget) this.foldTarget.focus()
  }

  // The tree's frame is replaced by a move, and its head's button with it.
  foldTargetConnected(button) {
    button.setAttribute("aria-expanded", String(!this.folded))
  }

  get folded() { return this.root.hasAttribute(FOLDED) }

  // --- the width --------------------------------------------------------------

  // The default again (a double click, Enter): the property and the stored
  // choice both go, so the stylesheet's own 17rem is what draws the column,
  // at any font size, and "the default" is what is remembered.
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

  // Everything that follows from the width, the fold and the window, said
  // again: whether the column is expanded (both fold buttons), and what the
  // separator tells a screen reader and its tooltip. Called on connect, on
  // every change of the width and of the fold, on `resize`, when a frame has
  // loaded and when the divider takes the focus.
  sync() {
    const folded = this.folded
    this.foldTargets.concat(this.unfoldTargets).forEach((button) => button.setAttribute("aria-expanded", String(!folded)))

    if (!this.hasDividerTarget) return
    const divider = this.dividerTarget
    const width = Math.round(this.width)
    divider.setAttribute("aria-valuemin", String(Math.round(this.least)))
    divider.setAttribute("aria-valuemax", String(Math.round(this.ceiling)))
    divider.setAttribute("aria-valuenow", String(width))
    const bubble = divider.querySelector("[data-tooltip]")
    if (bubble) bubble.textContent = messages(divider).t(this.tooltipKeyValue, { width })
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
    if (this.hasDividerTarget) this.dividerTarget.removeAttribute("data-dragging")
    this.root.removeAttribute(RESIZING)
    if (!pointer || !this.hasDividerTarget) return
    try {
      this.dividerTarget.releasePointerCapture(pointer.id)
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
  // keeps its least beside the sidebar (where that is a column).
  get ceiling() {
    const room = this.windowWidth - this.sidebar - this.editor
    return Math.max(this.least, Math.min(this.most, Math.floor(room)))
  }

  // The window's width the shell is laid out in: the root's box, which is
  // the window less the scrollbar's gutter. Not `clientWidth`, which leaves
  // out a scrollbar but not a gutter with none in it.
  get windowWidth() {
    return this.root.getBoundingClientRect().width
  }

  // The modules sidebar is a column of the grid from 1280px and a drawer
  // below (`.admin-shell` in the stylesheet). The breakpoint is a media
  // query's, in pixels at any font size; the column is 15rem.
  get sidebar() {
    return window.matchMedia("(min-width: 1280px)").matches ? this.sidebarValue * this.scale : 0
  }
}
