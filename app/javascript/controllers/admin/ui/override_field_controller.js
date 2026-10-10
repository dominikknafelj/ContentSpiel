import { Controller } from "@hotwired/stimulus"

// The Reset and library-text parts of a per-use override field (design pass
// round 2, handoff §10 A1; markup in `admin/shared/_override_field`). The
// override input itself belongs to the caller and is named by id: its
// placeholder is the library's text, which is what a blank override falls
// back to.
//
// Reset empties the input and dispatches a bubbling `input` on it, which the
// form's `admin--saving--autosave` queues like a keystroke -- so the cleared value is
// what gets saved, and the placeholder (the library text) is what shows.
// Nothing here talks to the server.
//
// `refresh` runs when the input changes and when its placeholder does
// (`admin--media-field` rewrites it when another image is chosen), so Reset
// and the library line show only while the field holds its own text, and the
// line always names the current library text.
export default class extends Controller {
  static targets = [ "reset", "library", "text" ]
  static values = { inputId: String }

  connect() {
    this.input = document.getElementById(this.inputIdValue)
    if (!this.input) return

    this.refresh = this.refresh.bind(this)
    this.input.addEventListener("input", this.refresh)
    this.observer = new MutationObserver(this.refresh)
    this.observer.observe(this.input, { attributes: true, attributeFilter: [ "placeholder" ] })
    this.refresh()
  }

  disconnect() {
    this.input?.removeEventListener("input", this.refresh)
    this.observer?.disconnect()
  }

  reset(event) {
    event?.preventDefault()
    if (!this.input) return

    this.input.value = ""
    this.input.dispatchEvent(new Event("input", { bubbles: true }))
    this.input.focus()
  }

  refresh() {
    const overridden = this.input.value !== ""
    const library = this.input.placeholder || ""

    this.resetTarget.hidden = !overridden
    this.textTarget.textContent = library
    this.libraryTarget.hidden = !overridden || library === ""
  }
}
