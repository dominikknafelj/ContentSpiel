import { Controller } from "@hotwired/stimulus"

// Where focus goes after the Media screen's side panel opens or closes (round 3,
// Task 8 fix round 1). Choosing a tile is a frame navigation: the frame render
// replaces the very link that had focus, so focus would fall to <body> and a
// keyboard user would have to tab back through up to 48 tiles and the pager to
// reach the panel. So:
//   * choosing a tile  -> focus the panel (`#media-panel`, tabindex -1);
//   * the panel's "×"  -> focus the tile that had been chosen.
// Nothing else moves focus: a plain page load, a language-tab switch and an
// autosave stream never register a `pending` move, so they cannot steal focus
// from where the editor is.
//
// The click only leaves a note (module state, which outlives the DOM it was made
// in); the NEXT `connect` -- the controller's element is re-rendered by the
// frame, and again by the visit Turbo promotes the frame navigation to --
// carries it out. It is kept for WINDOW_MS rather than consumed by the first
// connect, because that second render would drop focus again; `turbo:load`
// ends it once the promoted visit is done. A note older than WINDOW_MS (a
// click that went nowhere: a link opened in a new tab, a refused visit) is
// ignored, never acted on by some later, unrelated render.
const WINDOW_MS = 3000
let pending = null

export default class extends Controller {
  static targets = [ "panel" ]

  connect() {
    if (!pending) return
    if (Date.now() - pending.at > WINDOW_MS) {
      pending = null
      return
    }

    const note = pending
    // After the render settles: Turbo's own post-render work would otherwise win.
    requestAnimationFrame(() => this.moveFocus(note))
    document.addEventListener("turbo:load", () => { pending = null }, { once: true })
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
      document.querySelector(`#media-asset-${CSS.escape(String(note.id))} a`)?.focus()
    }
  }

  // A modified click opens a new tab/window: nothing changes here.
  modified(event) {
    return event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button > 0
  }
}
