import { Controller } from "@hotwired/stimulus"

// ⌘K / Ctrl+K "Jump to…" (design pass spec §5.6). The dialog and its
// results frame are rendered once in the layout
// (Admin::Shell::CommandPaletteComponent); this controller sits on <body>.
// Typing reloads the frame (debounced), the arrow keys move the selection
// (`aria-selected` on the <li role=option>), Enter follows the selected
// link. Following a link is a `_top` Turbo visit, whose page replacement
// closes the dialog (it is not part of the new body).
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.index = 0
    this.onKey = (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
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

  open() {
    if (!this.dialog || this.dialog.open) return
    this.input.value = ""
    this.load()
    this.dialog.showModal()
    this.input.focus()
  }

  search() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), 150)
  }

  load() {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", this.input.value)
    this.frame.src = url.toString()
  }

  loaded() { this.select(0) }

  move(event) {
    if (!["ArrowDown", "ArrowUp", "Enter"].includes(event.key)) return
    event.preventDefault()
    const options = this.options
    if (options.length === 0) return
    if (event.key === "Enter") return options[this.index]?.click()
    this.select((this.index + (event.key === "ArrowDown" ? 1 : -1) + options.length) % options.length)
  }

  select(index) {
    this.index = index
    this.options.forEach((option, i) => {
      option.parentElement.setAttribute("aria-selected", String(i === index))
      option.classList.toggle("bg-sunken", i === index)
      if (i === index) option.scrollIntoView({ block: "nearest" })
    })
  }
}
