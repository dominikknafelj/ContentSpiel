import { Controller } from "@hotwired/stimulus"

// CS Studio's mind graph (`admin/mind_graph/show`; mind graph canvas spec §4).
// Deliberately thin: every `controllers/admin/*` file is loaded on every CS
// Studio page, so the graph's own modules -- and, through its worker,
// d3-force -- are imported only here, only when this screen is on the page
// (`import()` of `mind_graph/app`, which the import map resolves but nothing
// preloads). What the graph does is in `app/javascript/mind_graph/`.
//
// `connect()` may be followed by `disconnect()` before the import has arrived
// (a quick visit away, a Turbo cache preview): `this.live` says whether this
// connection is still the current one, so a late import mounts nothing.
//
// `connect()` also takes back what a Turbo snapshot carries. Turbo caches the
// page as it stood when it was left -- `data-state="ready"`, `data-settled`,
// the counts, the canvas's name with its summary of them, the notice's lines,
// an open selection card and where it stood, the search's text and results,
// the list's rows, the zoom's figure, the number of pinned nodes and the
// button that releases them -- and Back restores exactly that, before
// anything has been fetched or laid out. All of it says what the screen
// SHOWS, so it is reset here, synchronously, and the app writes it again as it
// becomes true. Pins are among it on purpose: they live in the page that made
// them, and a visit that comes back starts with none. (The legend's
// checkboxes are restored too, and they are kept: the graph shows what the
// legend says. Their counts, and the names made of them, are taken back.)
// The legend's swatches and the "Status" key are not this controller's:
// `admin--mind-graph--swatches` draws the first again on its own connect, and
// the key is a dialog outside this element, opened by `admin--ui--dialog` and
// closed natively, in which the graph writes nothing.
//
// A failed `import()` is left unhandled on purpose: the rejection is a
// JavaScript error, loud in the console and in the system tests, and never a
// box that silently stays empty.
export default class extends Controller {
  static targets = ["canvas", "notice"]

  connect() {
    this.reset()
    const live = (this.live = Symbol("connection"))
    import("mind_graph/app").then(({ mount }) => {
      if (this.live === live) this.app = mount(this.element)
    })
  }

  disconnect() {
    this.live = null
    this.app?.destroy()
    this.app = null
  }

  filter() { this.app?.filter() }
  zoomIn() { this.app?.zoomIn() }
  zoomOut() { this.app?.zoomOut() }
  fit() { this.app?.fit() }
  releasePinned() { this.app?.releasePinned() }

  reset() {
    this.element.dataset.state = "loading"
    for (const name of ["data-settled", "data-nodes", "data-edges", "data-zoom", "data-labelled", "data-selected", "data-neighbours", "data-hovered", "data-pinned"]) this.element.removeAttribute(name)
    if (this.hasNoticeTarget) this.noticeTarget.replaceChildren()
    // The canvas's name: the app writes the counts into it once the data has
    // come, and the snapshot holds the counts of the visit that was left --
    // for good, if this load then fails. The server's own name is kept in
    // `data-label`, and is the name until there is something to count.
    if (this.hasCanvasTarget && this.canvasTarget.dataset.label) this.canvasTarget.setAttribute("aria-label", this.canvasTarget.dataset.label)
    // The legend's counts and the names made of them are the visit that was
    // left. The checkboxes themselves are the person's choice and are kept:
    // the graph shows what the legend says.
    for (const count of this.element.querySelectorAll("[data-legend-count]")) count.replaceChildren()
    for (const input of this.element.querySelectorAll("[data-mind-graph-legend] input")) input.removeAttribute("aria-label")
    // The search: the snapshot holds the typed text and the open results of
    // the visit that was left. Back shows the field empty and the list closed.
    const field = this.element.querySelector("[data-mind-graph-search] input")
    if (field) field.value = ""
    this.element.querySelector("[data-mind-graph-status]")?.replaceChildren()
    // The list: its rows are the visit that was left, and come back with the
    // data. The zoom's figure and "Release N pinned" are that visit's too.
    this.element.querySelector("[data-mind-graph-list]")?.replaceChildren()
    this.element.querySelector("[data-mind-graph-zoom]")?.replaceChildren()
    const release = this.element.querySelector("[data-mind-graph-release]")
    if (release) {
      release.hidden = true
      release.replaceChildren()
    }
    for (const floating of this.element.querySelectorAll("[data-mind-graph-card], [data-mind-graph-tooltip], [data-mind-graph-results]")) {
      floating.hidden = true
      floating.replaceChildren()
      // Where the script had put it (the card beside its node, the tooltip
      // beside the pointer).
      floating.removeAttribute("style")
      floating.removeAttribute("data-side")
      floating.removeAttribute("aria-labelledby")
    }
  }
}
