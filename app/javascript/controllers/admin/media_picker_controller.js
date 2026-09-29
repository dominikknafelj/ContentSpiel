import { Controller } from "@hotwired/stimulus"

// The one media picker (media library design spec §6, Task 8), on
// `Media::PickerComponent`'s `<dialog>` -- rendered once per CS Studio page
// by the admin layout. See that component's comment for where it's used.
//
// The contract with a field or editor that wants an image:
// - open it by dispatching `media-picker:open` on `window` with
//   `detail: { opener }` -- the element (a Choose button, the editor's
//   Image button) focus returns to afterwards;
// - receive `media-picker:picked` on that opener (it bubbles), with
//   `detail: { id, url, title, alt, caption }` -- `id` is what gets saved,
//   `url` a thumbnail to show, `alt`/`caption` the asset's own defaults in
//   the editing language (for the per-use fields' placeholders).
// Nothing is dispatched on Cancel or Escape: the opener simply gets focus
// back.
//
// `picked` is dispatched from the dialog's `close` handler, not straight
// from `#pick`: closing a modal dialog restores focus asynchronously, so
// dispatching first would let that restore land *after* whatever focus the
// opener's own handler moved (the rich-text editor opens its alt-text
// popover and focuses it) and steal it back.
//
// No browser dialogs: an upload's errors go into the Upload tab's own
// `role=alert` line.
export default class extends Controller {
  static targets = [ "tab", "panel", "frame", "file", "status", "error" ]
  static values = { libraryUrl: String, uploadUrl: String }

  static texts = {
    uploading: "Uploading…",
    uploadFailed: "Upload failed — check your connection",
    uploadRejected: "Upload failed"
  }

  connect() {
    this.opener = null
    this.pending = null
  }

  disconnect() {
    this.aborter?.abort()
  }

  open(event) {
    const opener = event.detail?.opener
    if (!opener) return

    this.opener = opener
    this.pending = null
    this.clearUpload()
    this.showTab("library")
    this.loadLibrary()
    if (!this.element.open) this.element.showModal()
    this.tabTargets[0]?.focus()
  }

  // A fresh load on every open: setting `src` to the URL it already has
  // wouldn't refetch, so a repeated open reloads the frame instead.
  loadLibrary() {
    const url = new URL(this.libraryUrlValue, window.location.href).toString()
    if (this.frameTarget.src === url) {
      this.frameTarget.reload()
    } else {
      this.frameTarget.src = url
    }
  }

  // A Library card's button (`Admin::MediaLibrary::GridComponent`, pick
  // mode): its whole payload arrives as one JSON action param.
  pick(event) {
    this.choose(event.params.asset)
  }

  choose(detail) {
    if (!detail || !Number.isInteger(detail.id)) return

    this.pending = detail
    this.element.close()
  }

  // The dialog's own `close` event -- after a pick, Cancel, or Escape (the
  // native `cancel` closes it too). Hands focus back to the opener, then
  // tells it what was picked, if anything.
  closed() {
    // Aborting only stops the browser waiting for an upload still in
    // flight -- if the request already reached the server, the asset is
    // created anyway (`Media::Upload` has no way to know the picker went
    // away). Nothing references it, so it shows up under the Media
    // module's "Unused" filter, where it can be deleted (cleanup is manual
    // only, global constraints).
    this.aborter?.abort()
    const opener = this.opener
    const detail = this.pending
    this.opener = null
    this.pending = null
    if (!opener || !opener.isConnected) return

    opener.focus()
    if (detail) this.dispatch("picked", { target: opener, prefix: "media-picker", detail })
  }

  // --- Tabs ----------------------------------------------------------------

  selectTab(event) {
    this.showTab(event.currentTarget.dataset.tab)
  }

  // Left/Right move between the two tabs (WAI-ARIA tabs pattern), with the
  // inactive one out of the tab order.
  tabKey(event) {
    if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return

    event.preventDefault()
    const index = this.tabTargets.indexOf(event.currentTarget)
    const next = this.tabTargets[(index + (event.key === "ArrowRight" ? 1 : -1) + this.tabTargets.length) % this.tabTargets.length]
    this.showTab(next.dataset.tab)
    next.focus()
  }

  showTab(name) {
    this.tabTargets.forEach((tab) => {
      const selected = tab.dataset.tab === name
      tab.setAttribute("aria-selected", selected ? "true" : "false")
      tab.tabIndex = selected ? 0 : -1
    })
    this.panelTargets.forEach((panel) => { panel.hidden = panel.dataset.tab !== name })
  }

  // --- Upload ----------------------------------------------------------------
  //
  // One file to `Admin::MediaAssetsController#create` (`Media::Upload`),
  // multipart `file` plus the layout's CSRF token. A 201 is picked straight
  // away -- a new upload has no default alt or caption yet; anything else
  // shows the response's `errors` inline and leaves the picker open.
  async upload() {
    const file = this.fileTarget.files[0]
    // Cleared at once, so choosing the same file again still fires `change`.
    this.fileTarget.value = ""
    if (!file) return

    this.aborter?.abort()
    this.aborter = new AbortController()
    this.errorTarget.textContent = ""
    this.statusTarget.textContent = this.constructor.texts.uploading

    const body = new FormData()
    body.append("file", file)

    let response
    try {
      response = await fetch(this.uploadUrlValue, {
        method: "POST",
        body,
        signal: this.aborter.signal,
        headers: { Accept: "application/json", "X-CSRF-Token": this.csrfToken() }
      })
    } catch (error) {
      if (error.name !== "AbortError") this.showUploadError([ this.constructor.texts.uploadFailed ])
      return
    }

    const json = await response.json().catch(() => ({}))

    if (response.status !== 201 || !Number.isInteger(json.id)) {
      this.showUploadError(Array.isArray(json.errors) && json.errors.length ? json.errors : [ this.constructor.texts.uploadRejected ])
      return
    }

    this.statusTarget.textContent = ""
    this.choose({ id: json.id, url: json.url, title: json.title || file.name, alt: "", caption: "" })
  }

  showUploadError(errors) {
    this.statusTarget.textContent = ""
    this.errorTarget.textContent = errors.join(". ")
  }

  clearUpload() {
    this.aborter?.abort()
    this.fileTarget.value = ""
    this.statusTarget.textContent = ""
    this.errorTarget.textContent = ""
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
