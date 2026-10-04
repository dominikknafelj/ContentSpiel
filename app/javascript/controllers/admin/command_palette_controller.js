import { Controller } from "@hotwired/stimulus"

// ⌘K / Ctrl+K "Jump to…" (design pass spec §5.6). The dialog and its
// results frame are rendered once in the layout
// (Admin::Shell::CommandPaletteComponent); this controller sits on <body>.
// Typing reloads the frame (debounced), the arrow keys move the selection
// (`aria-selected` on the <li role=option>, mirrored for the focused input
// as `aria-activedescendant`), Enter follows the selected link and
// ⌘/Ctrl+Enter opens it in a new tab (the dialog stays open, as in a browser's
// own ⌘-click). Following a link is a `_top` Turbo visit, whose page
// replacement closes the dialog (it is not part of the new body).
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.index = 0
    this.onKey = (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key?.toLowerCase() === "k") {
        event.preventDefault()
        this.open()
      }
    }
    window.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    window.removeEventListener("keydown", this.onKey)
    clearTimeout(this.timer)
  }

  get dialog() { return document.getElementById("command-palette") }
  get input() { return this.dialog.querySelector("input") }
  get frame() { return this.dialog.querySelector("turbo-frame") }
  get options() { return Array.from(this.frame.querySelectorAll("[role=option] a")) }

  // The query the server answered for what the frame currently shows (the
  // `data-query` the results fragment echoes), and the input's own value in
  // the same normal form (trimmed, capped at the server's 100 characters,
  // by code point like Ruby's `first`). They differ exactly while the
  // results are stale: between a keystroke and its response, or when an
  // older response arrived late.
  get renderedQuery() { return this.frame.querySelector("[data-query]")?.dataset.query }
  get query() { return Array.from(this.input.value.trim()).slice(0, 100).join("") }
  get stale() { return this.renderedQuery !== this.query }

  open() {
    if (!this.dialog || this.dialog.open) return
    this.input.value = ""
    this.pendingEnter = false
    this.load()
    // Unchanged (empty) query: the frame won't reload, so no `loaded`
    // follows -- put the selection back on the first row here.
    this.select(0)
    this.dialog.showModal()
    this.input.focus()
  }

  search() {
    clearTimeout(this.timer)
    this.pendingEnter = false
    // Stale from this keystroke on: no row is selected (so none can be
    // followed) until the response for this query has rendered.
    this.select(this.stale ? -1 : 0)
    this.timer = setTimeout(() => this.load(), 150)
  }

  load() {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", this.input.value)
    this.frame.src = url.toString()
  }

  // A response for a query the viewer has since changed is ignored (a newer
  // request is already on its way): the frame renders whichever response
  // lands last, so without this a slow earlier answer could replace a later one.
  loaded() {
    if (this.stale) return
    this.select(0)
    if (this.pendingEnter) {
      this.pendingEnter = false
      this.options[0]?.click()
    }
  }

  move(event) {
    if (!["ArrowDown", "ArrowUp", "Enter"].includes(event.key)) return
    event.preventDefault()
    // Enter while the results are stale waits for the matching response
    // and then follows its first row (or does nothing if it has none).
    if (event.key === "Enter" && this.stale) { this.pendingEnter = true; return }
    const options = this.options
    if (options.length === 0) return
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      // Stale results: the selected row may be for a query the viewer has
      // since changed, so do nothing rather than open the wrong thing (the
      // plain Enter above waits for the response; a new-tab open doesn't).
      if (this.stale) return
      const href = options[this.index]?.href
      if (href) window.open(href, "_blank", "noopener")
      return
    }
    if (event.key === "Enter") return options[this.index]?.click()
    if (this.stale) return
    this.select((this.index + (event.key === "ArrowDown" ? 1 : -1) + options.length) % options.length)
  }

  // Focus never leaves the input, so the selected row is announced through
  // the input's `aria-activedescendant`. It names the selected option's id,
  // and is removed whenever no row is selected (stale results, an empty
  // answer) -- an id that no longer exists must not be left behind.
  select(index) {
    this.index = index
    let selectedId = null
    this.options.forEach((option, i) => {
      option.parentElement.setAttribute("aria-selected", String(i === index))
      option.classList.toggle("bg-sunken", i === index)
      if (i === index) {
        option.scrollIntoView({ block: "nearest" })
        selectedId = option.parentElement.id
      }
    })
    if (selectedId) this.input.setAttribute("aria-activedescendant", selectedId)
    else this.input.removeAttribute("aria-activedescendant")
  }
}
