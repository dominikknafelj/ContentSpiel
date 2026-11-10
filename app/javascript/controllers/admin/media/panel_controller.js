import { Controller } from "@hotwired/stimulus"

// Where focus goes after the Media screen's rail opens or closes, on the
// library's grid. Choosing a tile is a frame navigation: the frame render
// replaces the very link that had focus, so focus would fall to <body> and a
// keyboard user would have to tab back through up to 48 tiles and the pager to
// reach the panel. So:
//   * choosing a tile  -> focus the panel (`#media-panel`, tabindex -1);
//   * a language tab   -> focus the panel again (the tabs are `_top` links:
//     the page is replaced and scrolled to the top, and in a narrow library
//     the rail sits under the grid -- the editor who switched language in the
//     panel would be back at the first tile);
//   * the rail's Close -> focus the tile that had been chosen, or the search
//     field when that tile is not on the page shown (another page of the
//     grid, a filter it doesn't match).
// Nothing else moves focus: a plain page load and an autosave stream never
// register a `pending` move, so they cannot steal focus from where the editor
// is.
//
// THE TAB IS KEPT across a choice. The rail is drawn again by the choice's
// frame render, with the server's default tab; the note carries the tab that
// was current, and the next connect writes it as the new rail's current value
// before the rail's own controller connects (it is inside this element, so
// it connects after it), and asks for it again with `admin--ui--rail:reveal`
// once the render has settled, in case it connected first. The focus then
// goes to the panel when it is shown, else to the kept tab.
//
// ESCAPE inside the rail presses Close, unless something inside takes it
// first: a field being typed in (an input, a textarea, a select, an editable
// region), the notes section (its composer and thread have their own
// Escape), or an open dialog or menu. A key another handler already used
// (`defaultPrevented`) is left alone too.
//
// The click only leaves a note (module state, which outlives the DOM it was
// made in); the NEXT `connect` carries it out -- the controller's element is
// re-rendered by the frame navigation, or by the visit a language tab is. The
// note is NOT spent by that first connect but kept until the navigation is
// over (`turbo:load`), and every connect in between acts on it: the element
// can be rendered more than once on the way -- known for certain for a tile
// activated twice in quick succession (a double click; Cuprite's
// `send_keys(:enter)`, which clicks before it types), which gets two frame
// renders, the second dropping the focus the first one gave. Such a double
// activation is promoted to no visit at all, so no `turbo:load` follows and
// the note then simply expires. A note older than WINDOW_MS (also a click
// that went nowhere: a link opened in a new tab, a refused visit) is ignored,
// never acted on by some later, unrelated render.
const WINDOW_MS = 3000
const TYPED = "input, textarea, select, [contenteditable]:not([contenteditable='false'])"
const OPEN_LAYER = "dialog[open], [role=menu]"
let pending = null

export default class extends Controller {
  static targets = [ "panel", "close" ]

  connect() {
    this.onTab = (event) => {
      if (event.target instanceof Element && event.target.closest(".admin-language-tabs a")) this.choose(event)
    }
    this.element.addEventListener("click", this.onTab)

    if (!pending) return
    if (Date.now() - pending.at > WINDOW_MS) {
      pending = null
      return
    }

    const note = pending
    if (note.tab) this.rail?.setAttribute("data-admin--ui--rail-current-value", note.tab)
    // After the render settles: Turbo's own post-render work would otherwise win.
    requestAnimationFrame(() => {
      if (note.tab) this.revealTab(note.tab)
      this.moveFocus(note)
      if (note.kind === "panel") this.focusTab()
    })
    document.addEventListener("turbo:load", () => { pending = null }, { once: true })
  }

  disconnect() {
    this.element.removeEventListener("click", this.onTab)
  }

  choose(event) {
    if (this.modified(event)) return
    pending = { kind: "panel", at: Date.now(), tab: this.currentTab() }
  }

  close(event) {
    if (this.modified(event)) return
    pending = { kind: "tile", id: event.params.tileId, at: Date.now() }
  }

  escape(event) {
    if (event.defaultPrevented || !this.hasCloseTarget) return
    const target = event.target
    if (!(target instanceof Element)) return
    if (target.closest(TYPED) || target.closest("#media-notes") || target.closest(OPEN_LAYER)) return
    event.preventDefault()
    this.closeTarget.click()
  }

  moveFocus(note) {
    if (note.kind === "panel") {
      if (this.hasPanelTarget) this.panelTarget.focus()
    } else {
      const tile = document.querySelector(`#media-asset-${CSS.escape(String(note.id))} a`)
      ;(tile || document.querySelector("#content input[type=search][name=q]"))?.focus()
    }
  }

  get rail() {
    return this.element.querySelector("#media-rail")
  }

  currentTab() {
    return this.rail?.querySelector("[role=tab][aria-selected=true]")?.dataset.key || null
  }

  revealTab(key) {
    const panel = [ ...(this.rail?.querySelectorAll("[role=tabpanel]") || []) ].find((candidate) => candidate.dataset.key === key)
    panel?.dispatchEvent(new CustomEvent("admin--ui--rail:reveal", { bubbles: true }))
  }

  // The panel is hidden where another tab is current: the focus goes to
  // that tab instead of falling to <body>.
  focusTab() {
    if (this.hasPanelTarget && this.panelTarget.checkVisibility()) return
    this.rail?.querySelector("[role=tab][aria-selected=true]")?.focus()
  }

  // A modified click opens a new tab/window: nothing changes here.
  modified(event) {
    return event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button > 0
  }
}
