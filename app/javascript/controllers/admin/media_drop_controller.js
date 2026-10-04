import { Controller } from "@hotwired/stimulus"

// Drop images anywhere on the Media screen (round 3, Task 9, handoff §4.6): while
// a drag that carries FILES is over the window, a full-screen overlay says "Drop
// images to upload"; the drop hands the files to whoever uploads
// (`admin--media-upload`, on the same element, over `admin--media-drop:dropped`).
//
// Only a drag that carries files is any of this controller's business -- never a
// SortableJS drag (it is pointer-driven, no drag events at all here, and its
// fallback drags no `Files`) and never a text or link drag, which have no
// `Files` among `dataTransfer.types`. For a file drag the browser's default
// (navigating away to show the file) is always prevented, even over a dialog:
// losing the page and its unsaved work to a mis-aimed drop is worse than a
// refused one.
//
// `dragenter`/`dragleave` fire for every element the pointer crosses, so the
// overlay follows a depth COUNT (enter +1, leave -1, gone at 0) rather than the
// last event, or it would flicker over every child. The count can still be wrong
// when a drag simply ends elsewhere: pressing Escape or leaving the window gives
// no reliable `dragleave` for an external drag. So the overlay also goes on an
// Escape key, a `dragend`, a leave with no `relatedTarget` (the pointer left the
// document), and when no `dragover` has arrived for a second -- a drag that is
// alive reports one at least every ~350 ms.
//
// The listeners are on `document` (the whole screen is the target), so they
// are removed in `disconnect`, or each visit to the screen would add another set.
const STALE_MS = 1000

export default class extends Controller {
  static targets = [ "overlay" ]

  connect() {
    this.depth = 0
    this.handlers = {
      dragenter: (event) => this.enter(event),
      dragover: (event) => this.over(event),
      dragleave: (event) => this.leave(event),
      drop: (event) => this.drop(event),
      dragend: () => this.hide(),
      keydown: (event) => { if (event.key === "Escape") this.hide() }
    }
    Object.entries(this.handlers).forEach(([ name, handler ]) => document.addEventListener(name, handler, name === "drop"))
  }

  disconnect() {
    Object.entries(this.handlers).forEach(([ name, handler ]) => document.removeEventListener(name, handler, name === "drop"))
    this.hide()
  }

  enter(event) {
    if (!this.carriesFiles(event)) return

    this.depth += 1
    this.show()
  }

  over(event) {
    if (!this.carriesFiles(event)) return

    // What tells the browser this page accepts a drop at all (without it `drop`
    // never fires).
    event.preventDefault()
    if (event.dataTransfer) event.dataTransfer.dropEffect = this.dialogOpen ? "none" : "copy"
    clearTimeout(this.stale)
    this.stale = setTimeout(() => this.hide(), STALE_MS)
    if (this.depth === 0) this.enter(event)
  }

  leave(event) {
    if (!this.carriesFiles(event)) return

    this.depth = Math.max(0, this.depth - 1)
    // A leave that goes to no element at all is the pointer leaving the window.
    if (this.depth === 0 || event.relatedTarget === null) this.hide()
  }

  // Capture phase: the file zone's own `drop` stops propagation (so a drop inside
  // it is not handled twice -- file_drop_controller.js), which would otherwise
  // leave this overlay up.
  drop(event) {
    if (!this.carriesFiles(event)) return

    event.preventDefault()
    this.hide()
    if (this.dialogOpen) return
    // The zone turns its own drop into a `change` on its input, which uploads.
    if (event.target instanceof Element && event.target.closest("[data-controller~='file-drop']")) return

    const files = Array.from(event.dataTransfer?.files || [])
    if (files.length > 0) this.dispatch("dropped", { detail: { files } })
  }

  show() {
    if (this.dialogOpen) return

    this.overlayTarget.hidden = false
  }

  hide() {
    this.depth = 0
    clearTimeout(this.stale)
    if (this.hasOverlayTarget) this.overlayTarget.hidden = true
  }

  carriesFiles(event) {
    return Array.from(event.dataTransfer?.types || []).includes("Files")
  }

  // Another modal owns the screen: a drop is not an upload for the page behind it.
  get dialogOpen() {
    return document.querySelector("dialog[open]") !== null
  }
}
