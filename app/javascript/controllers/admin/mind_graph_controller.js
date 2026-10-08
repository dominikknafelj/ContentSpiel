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
// the counts, the notice's lines, an open selection card, the search's text and results -- and Back restores
// exactly that, before anything has been fetched or laid out. All of it says
// what the screen SHOWS, so it is reset here, synchronously, and the app
// writes it again as it becomes true. (The filter's radios are restored too,
// and they are kept: the graph shows what the control says.)
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

  reset() {
    this.element.dataset.state = "loading"
    for (const name of ["data-settled", "data-nodes", "data-edges", "data-zoom", "data-labelled", "data-selected", "data-neighbours"]) this.element.removeAttribute(name)
    if (this.hasNoticeTarget) this.noticeTarget.replaceChildren()
    // The search: the snapshot holds the typed text and the open results of
    // the visit that was left. Back shows the field empty and the list closed.
    const field = this.element.querySelector("[data-mind-graph-search] input")
    if (field) field.value = ""
    this.element.querySelector("[data-mind-graph-status]")?.replaceChildren()
    for (const floating of this.element.querySelectorAll("[data-mind-graph-card], [data-mind-graph-tooltip], [data-mind-graph-results]")) {
      floating.hidden = true
      floating.replaceChildren()
    }
  }
}
