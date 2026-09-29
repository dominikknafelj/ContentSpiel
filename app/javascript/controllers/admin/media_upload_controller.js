import { Controller } from "@hotwired/stimulus"

// The Media module's own multi-file upload (media library design spec §6,
// global constraints): drag and drop onto this controller's own element, or
// the plain file picker it wraps -- either way, one POST per file straight
// to `Admin::MediaController#create` (`Media::Upload` underneath), never a
// batch request. That's what keeps one refused or oversized file (an SVG,
// something over 10 MB) from blocking its siblings, and gives each its own
// inline error line next to its own filename -- there is no browser
// `alert()`/`confirm()` anywhere in this controller (spec: "no browser
// dialogs").
//
// A successful batch reloads the page once every request in it has settled:
// the grid has no partial-refresh endpoint of its own (unlike an autosave
// form's own Turbo Stream), and this is always a top-level page, never a
// `<turbo-frame>` this could instead ask to reload -- so a plain, real
// navigation is both the simplest and the most honest way to show the new
// cards, exactly as if the editor had reloaded by hand.
export default class extends Controller {
  static targets = [ "input", "list" ]
  static values = { url: String }

  filesSelected() {
    this.upload(Array.from(this.inputTarget.files))
    // Cleared immediately (not after the batch settles): re-picking the
    // exact same file a second time wouldn't otherwise fire another
    // `change` event at all, since the input's own value hasn't changed
    // from the browser's point of view.
    this.inputTarget.value = ""
  }

  dragOver(event) {
    // Only a drag carrying files is any of this controller's business --
    // preventing default on every dragover is what tells the browser this
    // element accepts a drop at all (without it, `drop` below never fires).
    event.preventDefault()
  }

  drop(event) {
    event.preventDefault()
    const files = event.dataTransfer?.files
    if (files && files.length > 0) this.upload(Array.from(files))
  }

  async upload(files) {
    if (files.length === 0) return

    const outcomes = await Promise.all(files.map((file) => this.uploadOne(file)))

    if (outcomes.some((ok) => ok)) window.location.reload()
  }

  // One file, one request, one status line -- returns whether it
  // succeeded, so `#upload` above knows whether a reload is worth doing at
  // all (a batch that was entirely refused leaves the grid exactly as it
  // was, with every error still readable in place).
  async uploadOne(file) {
    const row = this.addRow(file.name)

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        body: this.formData(file),
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        }
      })

      const body = await response.json().catch(() => ({}))

      if (response.ok) {
        row.textContent = `${file.name} — uploaded`
        return true
      }

      this.showError(row, file.name, body.errors)
      return false
    } catch (error) {
      this.showError(row, file.name, [ "Couldn't upload — check your connection" ])
      return false
    }
  }

  formData(file) {
    const data = new FormData()
    data.append("file", file)
    return data
  }

  addRow(name) {
    const row = document.createElement("li")
    row.textContent = `${name} — Uploading…`
    this.listTarget.appendChild(row)
    return row
  }

  showError(row, name, errors) {
    row.textContent = `${name} — ${(errors && errors.length > 0 ? errors : [ "Couldn't upload" ]).join(", ")}`
    row.classList.add("text-danger-ink")
  }
}
