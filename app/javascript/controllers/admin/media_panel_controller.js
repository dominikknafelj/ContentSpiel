import { Controller } from "@hotwired/stimulus"

// Where focus goes after the Media screen's side panel opens or closes (round 3,
// Task 8 fix round 1). Choosing a tile is a frame navigation: the frame render
// replaces the very link that had focus, so focus would fall to <body> and a
// keyboard user would have to tab back through up to 48 tiles and the pager to
// reach the panel. So:
//   * choosing a tile  -> focus the panel (`#media-panel`, tabindex -1);
//   * the panel's "×"  -> focus the tile that had been chosen.
//   * a language tab   -> focus the panel again (the tabs are `_top` links:
//     the page is replaced and scrolled to the top, and below 1024px the
//     panel sits under the grid -- the editor who switched language in the
//     panel would be back at the first tile);
//   * the panel's "×"  -> focus the tile that had been chosen, or the search
//     field when that tile is not on the page shown (another page of the
//     grid, a filter it doesn't match).
// Nothing else moves focus: a plain page load and an autosave stream never
// register a `pending` move, so they cannot steal focus from where the editor
// is.
//
// The click only leaves a note (module state, which outlives the DOM it was
// made in); the NEXT `connect` -- the controller's element is re-rendered by
// the frame navigation, or by the visit a language tab is -- carries it out
// and spends it. (The visit Turbo promotes a frame navigation to renders
// nothing, so there is no second connect to keep the note for.) A note older
// than WINDOW_MS (a click that went nowhere: a link opened in a new tab, a
// refused visit) is ignored, never acted on by some later, unrelated render.
const WINDOW_MS = 3000
let pending = null

export default class extends Controller {
  static targets = [ "panel" ]

  connect() {
    this.onTab = (event) => {
      if (event.target instanceof Element && event.target.closest(".admin-language-tabs a")) this.choose(event)
    }
    this.element.addEventListener("click", this.onTab)

    const note = pending
    pending = null
    if (!note || Date.now() - note.at > WINDOW_MS) return
    // After the render settles: Turbo's own post-render work would otherwise win.
    requestAnimationFrame(() => this.moveFocus(note))
  }

  disconnect() {
    this.element.removeEventListener("click", this.onTab)
  }

  choose(event) {
    if (this.modified(event)) return
    pending = { kind: "panel", at: Date.now() }
  }

  close(event) {
    if (this.modified(event)) return
    pending = { kind: "tile", id: event.params.tileId, at: Date.now() }
  }

  moveFocus(note) {
    if (note.kind === "panel") {
      if (this.hasPanelTarget) this.panelTarget.focus()
    } else {
      const tile = document.querySelector(`#media-asset-${CSS.escape(String(note.id))} a`)
      ;(tile || document.querySelector("#content input[type=search][name=q]"))?.focus()
    }
  }

  // A modified click opens a new tab/window: nothing changes here.
  modified(event) {
    return event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button > 0
  }
}
