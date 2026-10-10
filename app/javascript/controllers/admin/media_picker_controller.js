import { Controller } from "@hotwired/stimulus"
import { UploadTiles, updateCounts } from "media/upload_tiles"

// The one media picker (media library design spec §6, Task 8; round 3, Task 9),
// on `Media::PickerComponent`'s `<dialog>` -- rendered once per CS Studio page by
// the admin layout. See that component's comment for where it's used and how it
// is built; `admin--media-select` (the same element) owns choosing a tile.
//
// The contract with a field or editor that wants an image:
// - open it by dispatching `media-picker:open` on `window` with
//   `detail: { opener }` -- the element (a Choose button, the editor's
//   Image button) focus returns to afterwards;
// - receive `media-picker:picked` on that opener (it bubbles), with
//   `detail: { id, url, title, alt, caption }` -- `id` is what gets saved,
//   `url` a thumbnail to show, `alt`/`caption` the asset's own defaults in
//   the editing language (for the per-use fields' placeholders).
// Nothing is dispatched on Cancel, × or Escape: the opener simply gets focus
// back.
//
// `picked` is dispatched from the dialog's `close` handler, not straight
// from `#choose`: closing a modal dialog restores focus asynchronously, so
// dispatching first would let that restore land *after* whatever focus the
// opener's own handler moved (the rich-text editor opens its alt-text
// popover and focuses it) and steal it back.
//
// Escape: the first one, while the search box holds text, clears the search (the
// grid answers at once) and keeps the dialog open; the next one -- or the first,
// with nothing typed -- closes it. Chrome fires the native `cancel` for the key
// whether or not `keydown` was prevented, so both listeners cooperate through one
// flag rather than trusting either to be the only one that runs.
//
// Upload (the header button, then the file input) puts a progress tile per file at
// the start of the grid (`media/upload_tiles.js`, one at a time); the first to
// finish is selected, so Use image is one click away. A refused file keeps its
// tile with the server's reason. No browser dialogs anywhere.
export default class extends Controller {
  static targets = [ "frame", "file", "status" ]
  static values = { gridUrl: String, uploadUrl: String }

  connect() {
    this.opener = null
    this.pending = null
    this.escapeCleared = false
    this.uploads = new UploadTiles({
      url: this.uploadUrlValue,
      grid: () => this.frameTarget.querySelector("ul.admin-media-grid"),
      fields: () => this.searchValue ? { q: this.searchValue } : {},
      onUploaded: (done) => this.uploaded(done),
      announce: (text) => { this.statusTarget.textContent = text }
    })
  }

  disconnect() {
    this.uploads?.abort()
  }

  open(event) {
    const opener = event.detail?.opener
    if (!opener) return

    this.opener = opener
    this.pending = null
    this.selectNextUpload = false
    this.uploads.abort()
    this.statusTarget.textContent = ""
    this.dispatch("reset")
    this.focusSearchOnLoad = true
    this.loadGrid()
    if (!this.element.open) this.element.showModal()
  }

  // A fresh load on every open: setting `src` to the URL it already has
  // wouldn't refetch, so a repeated open reloads the frame instead.
  loadGrid() {
    const url = new URL(this.gridUrlValue, window.location.href).toString()
    if (this.frameTarget.src === url) {
      this.frameTarget.reload()
    } else {
      this.frameTarget.src = url
    }
  }

  // The grid arrived or navigated (search, segment, page): live upload tiles go
  // back at the start of it, and the first time, the search box takes focus --
  // unless the editor has already moved on to something else in the dialog.
  gridLoaded(event) {
    if (event.target !== this.frameTarget) return

    this.uploads.reattach()
    if (!this.focusSearchOnLoad) return

    this.focusSearchOnLoad = false
    const active = document.activeElement
    if (active === this.element || active === document.body || active?.dataset?.action?.includes("admin--media-picker#browse")) {
      this.search?.focus()
    }
  }

  get search() {
    return this.frameTarget.querySelector("input[type=search]")
  }

  get searchValue() {
    return this.search?.value || ""
  }

  // The select controller's `chosen`: its detail is the payload.
  chosen(event) {
    this.choose(event.detail)
  }

  choose(detail) {
    if (!detail || !Number.isInteger(detail.id)) return

    this.pending = detail
    this.element.close()
  }

  // × and Cancel.
  dismiss() {
    this.element.close()
  }

  // The dialog's own `close` event -- after a pick, Cancel, ×, or Escape (the
  // native `cancel` closes it too). Hands focus back to the opener, then
  // tells it what was picked, if anything.
  closed() {
    // Aborting only stops the browser waiting for an upload still in
    // flight -- if the request already reached the server, the asset is
    // created anyway (`Media::Upload` has no way to know the picker went
    // away). Nothing references it, so it shows up under the Media
    // module's "Unused" filter, where it can be deleted (cleanup is manual
    // only, global constraints).
    this.uploads.abort()
    const opener = this.opener
    const detail = this.pending
    this.opener = null
    this.pending = null
    if (!opener || !opener.isConnected) return

    opener.focus()
    if (detail) this.dispatch("picked", { target: opener, prefix: "media-picker", detail })
  }

  // --- Escape ----------------------------------------------------------------

  keydown(event) {
    if (event.key !== "Escape" || !this.clearSearch(event.target)) return

    event.preventDefault()
    // The native `cancel` that follows this same key press must not close it.
    this.escapeCleared = true
    setTimeout(() => { this.escapeCleared = false }, 0)
  }

  cancel(event) {
    if (this.escapeCleared || this.clearSearch(event.target === this.element ? this.search : event.target)) event.preventDefault()
  }

  // True when the search box held text and was emptied. `change` (not `input`)
  // so `admin--ui--auto-submit` answers at once instead of after its typing delay.
  clearSearch(field) {
    const search = this.search
    if (!search || (field !== search && field !== this.element) || search.value === "") return false

    search.value = ""
    search.dispatchEvent(new Event("change", { bubbles: true }))
    return true
  }

  // --- Upload ----------------------------------------------------------------

  // The header's Upload button opens the (visually hidden, labelled) file input.
  browse() {
    this.fileTarget.click()
  }

  upload() {
    const files = Array.from(this.fileTarget.files)
    // Cleared at once, so choosing the same file again still fires `change`.
    this.fileTarget.value = ""
    if (files.length === 0) return

    this.selectNextUpload = true
    this.uploads.add(files)
  }

  // A finished upload: the counts follow it, and the first of the batch is the
  // selection (handoff C36b) -- selected, not chosen: the editor confirms.
  uploaded({ json, tile }) {
    updateCounts(json.counts, { picker: true })
    if (!this.selectNextUpload || !tile) return

    const raw = tile.querySelector("[data-admin--media-select-asset-param]")?.getAttribute("data-admin--media-select-asset-param")
    if (!raw) return

    this.selectNextUpload = false
    this.dispatch("uploaded", { detail: { payload: JSON.parse(raw) } })
  }
}
