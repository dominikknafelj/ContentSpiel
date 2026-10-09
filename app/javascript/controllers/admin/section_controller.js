import { Controller } from "@hotwired/stimulus"

// One block's form open per section (sections spec §4.3).
//
// EVERY FORM IS ALREADY IN THE PAGE. A section renders each of its blocks'
// forms as a hidden panel under its lanes (`Admin::BlockCardComponent`,
// `placement: :panel`), and this controller only shows one and hides the
// rest. That is the whole point of the design: a form that is never removed
// stays registered with the write queue (`autosave/queue.js`), keeps its
// debounce timer, its queued or in-flight save and its save state -- paused
// by a 409, failed -- exactly as a card's does, so opening, closing and
// switching need no request and can lose nothing. Do not turn this into
// "fetch the form when its tile is pressed": the form leaving the document
// is what the queue's drain exists to guard against.
//
// CLOSING SENDS. A form being hidden is told to send what it holds now
// (`admin--autosave#saveNow`): an edit inside its debounce is otherwise only
// sent by its timer, a second later, with nothing on screen to say so. An
// unchanged form sends nothing and a paused one refuses, as always. Hiding
// itself stops nothing: a save queued or on the wire is answered into the
// hidden form's status line and base field like any other.
//
// WHICH FORM IS OPEN IS READ FROM THE PAGE, NOT REMEMBERED HERE (`openId`):
// the open panel is the one that is not `hidden`. A section's card is moved
// in the DOM by a drag or the keyboard path of `admin--blocks`, and Stimulus
// then disconnects every target and connects it again -- so anything this
// controller kept beside the DOM would have to be rebuilt or would be wrong:
// a remembered id cleared when "its panel left" forgot a form that was still
// showing, and the next tile pressed opened a second one beside it. The
// panel's own `hidden` moves with the panel, as a form's save state moves
// with the form (`saveStates` in `admin--autosave`). For the same reason a
// panel that really does leave (its block deleted or moved out) needs no
// bookkeeping: with it gone, nothing is open.
export default class extends Controller {
  static targets = ["tile", "panel"]

  // A block added to a column opens at once: the server marks its panel
  // `data-open`. Tile and panel arrive in one answer but as two streams, so
  // whichever connects second finds the other.
  tileTargetConnected(tile) { this.openIfNew(tile.dataset.blockId) }
  panelTargetConnected(panel) { this.openIfNew(panel.dataset.blockId) }

  openIfNew(id) {
    const panel = this.panelFor(id)
    if (!panel || !this.tileFor(id) || !panel.hasAttribute("data-open")) return
    panel.removeAttribute("data-open")
    this.open(id, { focus: true })
  }

  // The block whose form is showing, or undefined.
  get openId() { return this.panelTargets.find((panel) => !panel.hidden)?.dataset.blockId }

  toggle(event) {
    const id = event.currentTarget.closest("[data-block-id]").dataset.blockId
    if (this.openId === id) this.close()
    else this.open(id)
  }

  open(id, { focus = false } = {}) {
    const panel = this.panelFor(id)
    if (!panel) return
    if (this.openId && this.openId !== id) this.close({ refocus: false })

    panel.hidden = false
    this.faceFor(id)?.setAttribute("aria-expanded", "true")
    if (focus) panel.querySelector("input:not([type=hidden]), textarea, select, [contenteditable=true]")?.focus()
  }

  // Also the panel's own Close button. Focus goes back to the tile: the
  // field or button that had it is about to be hidden, and focus would fall
  // to <body>, the top of the page for a keyboard user. Not when another
  // tile is being opened -- that tile was just pressed and has the focus.
  close({ refocus = true } = {}) {
    const id = this.openId
    if (!id) return

    const panel = this.panelFor(id)
    this.sendNow(panel)
    panel.hidden = true
    const face = this.faceFor(id)
    face?.setAttribute("aria-expanded", "false")
    if (refocus) face?.focus()
  }

  // Escape closes the form -- unless it was meant for something open inside
  // it: a menu, a suggestion list or a dialog closes itself on Escape, and
  // the same key press must not also take the form away. Their listeners sit
  // on descendants of the card, so they have run by the time this one does,
  // and each marks the press as handled (`admin--menu#keydown`, the rich-text
  // popover and `admin--blocks#key` for a picked-up card call
  // `preventDefault`; `admin--chip-input` and the link search also stop it
  // from getting here at all). The checks after `defaultPrevented` are for a
  // widget that closes on Escape without saying so: the press is left alone
  // while it comes from inside a menu, a list or an open dialog, or while a
  // suggestion list of the open form is showing.
  escape(event) {
    const id = this.openId
    if (!id || event.defaultPrevented) return
    const target = event.target
    if (target.closest("[role=menu], [role=listbox], dialog[open]")) return
    if (target.closest("[data-controller~='admin--menu']")?.querySelector("[aria-expanded=true]")) return
    if (this.panelFor(id)?.querySelector("[role=listbox]:not([hidden])")) return

    event.preventDefault()
    this.close()
  }

  sendNow(panel) {
    for (const form of panel.querySelectorAll("form[data-controller~='admin--autosave']")) {
      this.application.getControllerForElementAndIdentifier(form, "admin--autosave")?.saveNow()
    }
  }

  panelFor(id) { return this.panelTargets.find((panel) => panel.dataset.blockId === id) }
  tileFor(id) { return this.tileTargets.find((tile) => tile.dataset.blockId === id) }
  faceFor(id) { return this.tileFor(id)?.querySelector(".admin-block-tile__face") }
}
