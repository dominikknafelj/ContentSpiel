import { Controller } from "@hotwired/stimulus"
import { UploadTiles, updateCounts, uploadWords } from "media/upload_tiles"
import { messages } from "i18n/messages"

// The place the picker showed last, per browser (media-folders spec §8, the
// owner's ruling): `all`, `none` or a folder's id. Storage may be refused
// (a private window, blocked site data) or hold anything, so every read and
// write is guarded and anything else is All media.
const PLACE_KEY = "cs.media.picker.place"
const PLACE = /^(all|none|[1-9]\d{0,18})$/

function rememberedPlace() {
  try {
    const place = window.localStorage.getItem(PLACE_KEY)
    return PLACE.test(place ?? "") ? place : "all"
  } catch {
    return "all"
  }
}

function remember(place) {
  try { window.localStorage.setItem(PLACE_KEY, place) } catch { /* storage refused: the next open is All media */ }
}

function forget() {
  try { window.localStorage.removeItem(PLACE_KEY) } catch { /* storage refused: nothing was kept */ }
}

// The one media picker, on `Admin::Ui::MediaPickerComponent`'s `<dialog>` -- rendered
// once per CS Studio page by
// the admin layout. See that component's comment for where it's used and how it
// is built; `admin--media--select` (the same element) owns choosing a tile.
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
// SEVERAL (the Gallery card, the card StudioGallery, D4): `detail: { opener,
// multiple: true, max, chosen, focus }`, `max` what the gallery still takes,
// `chosen` the ids already in it, and `focus: "places"` (optional) to put the
// focus on the places rather than the search when the grid arrives. The title
// reads "Add images", `admin--media--select` keeps the list (its `reset`
// carries the opening), and `picked` answers `detail: { items: [{ id, url,
// title, alt, caption }, ...] }` in the order chosen. Every other opening is
// a single one, and its title and primary are put back.
//
// A WHOLE FOLDER (StudioGallery D4, gallery spec §10.4): in a folder's place
// of a multiple opening, after each load of the frame and each change of the
// choice (`admin--media--select:changed`), the folder's row
// (`#media-picker-folder`, drawn hidden) asks its address what the folder
// adds: `limit` what the gallery takes after the choice, `except` the ids in
// the gallery and the ones chosen. It says "Add all 31 new images in this
// folder", or "Add the first 12 of 31 new images" past that, and is shown
// while some image is new (`data-media-folder-total` holds the count asked
// last). Its press hands back the choice, then the folder's images, oldest
// first, and closes. Only the last question's answer is drawn; a failed one
// leaves the row hidden, and the grid is still there to choose from.
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
//
// PLACES (the card's D12): the frame opens at the place it showed last
// (`PLACE_KEY`), and after each load of it the place it now shows is read from
// `#media-picker-place` inside it (never the frame's own attributes, which
// Turbo does not copy): stored, or forgotten when the server answered All
// media for a folder that is gone (`data-media-place-gone`); said before
// Upload ("Uploads go into …"); and its row, which the server draws
// selected, scrolled into view in the list. Uploads go to that place. Below
// 640px the places are a select, whose change loads the frame (`place`).
export default class extends Controller {
  static targets = [ "frame", "file", "status", "uploadInto", "title" ]
  static values = { gridUrl: String, uploadUrl: String, tileClass: String, buttonClass: String }

  connect() {
    this.opener = null
    this.multiple = false
    this.opening = null
    this.chosenItems = []
    this.folderItems = []
    this.folderRequest = null
    this.pending = null
    this.escapeCleared = false
    this.gridPending = false
    this.shownPlace = "all"
    this.uploads = new UploadTiles({
      url: this.uploadUrlValue,
      grid: () => this.frameTarget.querySelector("ul.admin-media-grid"),
      fields: () => this.uploadFields(),
      onUploaded: (done) => this.uploaded(done),
      announce: (text) => { this.statusTarget.textContent = text },
      tileClass: this.tileClassValue,
      buttonClass: this.buttonClassValue,
      words: uploadWords(this.element)
    })
  }

  disconnect() {
    this.uploads?.abort()
    this.folderRequest?.abort()
  }

  open(event) {
    const opener = event.detail?.opener
    if (!opener) return

    const multiple = event.detail.multiple === true
    this.multiple = multiple
    this.opener = opener
    this.pending = null
    this.selectNextUpload = false
    this.uploads.abort()
    this.statusTarget.textContent = ""
    this.titleTarget.textContent = messages(this.element).t(multiple ? "components.ui.media_picker.title_multiple" : "components.ui.media_picker.title")
    this.opening = multiple ? this.severalOpening(event.detail) : null
    this.chosenItems = []
    this.folderItems = []
    this.dispatch("reset", { detail: this.opening || {} })
    this.focusOnLoad = multiple && event.detail.focus === "places" ? "places" : "search"
    this.loadGrid()
    if (!this.element.open) this.element.showModal()
  }

  // What a multiple opening hands `admin--media--select`: `max` a whole
  // number, `present` the ids that are (anything else in `chosen` is
  // dropped).
  severalOpening({ max, chosen }) {
    return {
      multiple: true,
      max: Number.isInteger(max) && max > 0 ? max : 0,
      present: Array.isArray(chosen) ? chosen.filter((id) => Number.isInteger(id)) : []
    }
  }

  // A fresh load on every open: setting `src` to the URL it already has
  // wouldn't refetch, so a repeated open reloads the frame instead.
  //
  // The last open's grid is taken out first. Left standing while the new one
  // loads, it is an old library a person can press in, and a press the new
  // grid is drawn in the middle of (down on an old tile, up on its new twin)
  // is no click at all: nothing is selected and Use image stays off.
  //
  // A load still under way -- the picker was closed and opened again before
  // its grid was drawn -- is that fresh grid already, and is let finish. A
  // second load would draw over it: the search box the first grid was drawn
  // with, and the focus `gridLoaded` gave it, would be taken out from under
  // the person, and the focus left on the page's body.
  loadGrid() {
    if (this.gridPending) return

    this.gridPending = true
    this.frameTarget.replaceChildren()
    const address = new URL(this.gridUrlValue, window.location.href)
    const place = rememberedPlace()
    // A load that opens All media says so at once: an upload sent before it
    // arrives goes into no folder, as the sentence says.
    if (place === "all") this.showAllMedia()
    else address.searchParams.set("folder", place)
    const url = address.toString()
    if (this.frameTarget.src === url) {
      this.frameTarget.reload()
    } else {
      this.frameTarget.src = url
    }
  }

  // The grid arrived or navigated (search, segment, page): live upload tiles go
  // back at the start of it, and the first time, the search box takes focus
  // (or, asked with `focus: "places"`, the place shown) -- unless the editor
  // has already moved on to something else in the dialog.
  gridLoaded(event) {
    if (event.target !== this.frameTarget) return

    this.gridPending = false
    this.uploads.reattach()
    this.showPlace()
    this.askFolder()
    if (!this.focusOnLoad) return

    const focus = this.focusOnLoad
    this.focusOnLoad = null
    const active = document.activeElement
    if (active === this.element || active === document.body || active?.dataset?.action?.includes("admin--media--picker#browse")) {
      if (focus === "places") this.placeControl()?.focus({ preventScroll: true })
      else this.search?.focus()
    }
  }

  // The places' control for the place shown: the select below 640px, its
  // row's link from there.
  placeControl() {
    const select = this.frameTarget.querySelector("#media-picker-place-select")
    if (select?.checkVisibility()) return select

    return this.frameTarget.querySelector(`[id="media-picker-place-row-${this.shownPlace}"] a`)
  }

  // The place the frame now shows: kept for the next open (or forgotten, a
  // folder gone), said before Upload, and its row scrolled into the list's
  // view. A press on a place (a row, the select) lost its control with the
  // frame's old body: the new body's control for the place takes the focus.
  showPlace() {
    const marker = this.frameTarget.querySelector("#media-picker-place")
    if (!marker) return

    const place = marker.dataset.mediaPlace
    if (marker.hasAttribute("data-media-place-gone")) forget()
    else remember(place)
    this.shownPlace = place

    const words = messages(this.element)
    this.uploadIntoTarget.textContent = /^\d+$/.test(place)
      ? words.t("components.ui.media_picker.upload_into", { name: marker.dataset.mediaPlaceName })
      : words.t("components.ui.media_picker.upload_nowhere")

    const row = this.frameTarget.querySelector(`[id="media-picker-place-row-${place}"]`)
    if (row) this.scrollIntoList(row)

    if (!this.refocusPlace) return
    this.refocusPlace = false
    const active = document.activeElement
    if (active !== document.body && active !== this.element) return
    this.placeControl()?.focus({ preventScroll: true })
  }

  showAllMedia() {
    this.shownPlace = "all"
    this.uploadIntoTarget.textContent = messages(this.element).t("components.ui.media_picker.upload_nowhere")
  }

  // Only the list scrolls: the dialog and the page behind it stay put
  // (`scrollIntoView` would move every scrolling box above the row).
  scrollIntoList(row) {
    const list = row.closest("nav")
    if (!list || !list.checkVisibility()) return

    const box = list.getBoundingClientRect()
    const edge = row.getBoundingClientRect()
    if (edge.top < box.top) list.scrollTop -= box.top - edge.top
    else if (edge.bottom > box.bottom) list.scrollTop += edge.bottom - box.bottom
  }

  // A row of the list was pressed (its link loads the frame by itself).
  placePressed() {
    this.refocusPlace = true
  }

  // The select below 640px: its option names the address its row links to.
  place(event) {
    const href = event.target.selectedOptions[0]?.dataset.href
    if (!href) return

    this.refocusPlace = true
    this.frameTarget.src = new URL(href, window.location.href).toString()
  }

  // --- A whole folder --------------------------------------------------------

  // `admin--media--select`'s choice as it stands: the folder's row asks again
  // without it.
  choiceChanged(event) {
    if (!this.multiple) return

    this.chosenItems = Array.isArray(event.detail?.items) ? event.detail.items : []
    this.askFolder()
  }

  // What the folder shown adds to the gallery, asked of its row's address.
  // A question still under way is dropped: only the last is drawn.
  askFolder() {
    this.folderRequest?.abort()
    this.folderRequest = null
    const row = this.frameTarget.querySelector("#media-picker-folder")
    if (!row || !this.multiple || !this.opening) return

    const room = this.opening.max - this.chosenItems.length
    if (room <= 0) {
      row.hidden = true
      return
    }

    const address = new URL(row.dataset.url, window.location.href)
    address.searchParams.set("limit", String(room))
    address.searchParams.set("except", [ ...this.opening.present, ...this.chosenItems.map((item) => item.id) ].join(","))
    const request = new AbortController()
    this.folderRequest = request
    fetch(address, { headers: { Accept: "application/json" }, credentials: "same-origin", signal: request.signal })
      .then((response) => (response.ok ? response.json() : null))
      .then((answer) => {
        if (request !== this.folderRequest || !row.isConnected) return

        this.folderRequest = null
        this.showFolder(row, answer)
      })
      // Dropped for a later question, or the network failed: the row stays
      // as it is, hidden on a frame's first answer.
      .catch(() => {})
  }

  showFolder(row, answer) {
    const total = Number.isInteger(answer?.total) ? answer.total : 0
    this.folderItems = Array.isArray(answer?.items) ? answer.items.filter((item) => Number.isInteger(item?.id)) : []
    const count = this.folderItems.length
    const words = messages(this.element)
    const button = row.querySelector("[data-media-folder-add]")
    if (button) {
      button.textContent = total > count
        ? words.t("components.ui.media_picker.add_folder_first", { count, total })
        : words.t("components.ui.media_picker.add_folder", { count: total })
    }
    row.dataset.mediaFolderTotal = String(total)
    row.hidden = count === 0
  }

  // The folder's button: the choice in its order, then the folder's images
  // the last answer named, up to what the gallery takes.
  addFolder() {
    if (!this.multiple || !this.opening) return

    const items = [ ...this.chosenItems ]
    const ids = new Set(items.map((item) => item.id))
    for (const item of this.folderItems) {
      if (items.length >= this.opening.max) break
      if (ids.has(item.id)) continue

      items.push(item)
      ids.add(item.id)
    }
    this.choose({ items })
  }

  // What an upload sends beside its file: the search shown (the counts it
  // answers are of it) and the place, whose folder the file goes into.
  uploadFields() {
    const fields = {}
    if (this.searchValue) fields.q = this.searchValue
    if (this.shownPlace !== "all") fields.folder = this.shownPlace
    return fields
  }

  // The load ended with no grid (the network failed, or the answer held no
  // such frame): the next open asks again.
  gridFailed(event) {
    if (event.target === this.frameTarget) this.gridPending = false
  }

  get search() {
    return this.frameTarget.querySelector("input[type=search]")
  }

  get searchValue() {
    return this.search?.value || ""
  }

  // The select controller's `chosen`: its detail is the payload (one image's
  // keys, or a multiple opening's `items`).
  chosen(event) {
    this.choose(event.detail)
  }

  choose(detail) {
    const several = Array.isArray(detail?.items) && detail.items.length > 0 && detail.items.every((item) => Number.isInteger(item?.id))
    if (!several && !Number.isInteger(detail?.id)) return

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
  //
  // The event comes a task after the close itself, so a picker opened again
  // at once (Escape, then Space on the same button) is already open when the
  // last close's event arrives: that one is not this open's to answer, and
  // acting on it would forget the new opener before its own close.
  closed() {
    if (this.element.open) return

    // Aborting only stops the browser waiting for an upload still in
    // flight -- if the request already reached the server, the asset is
    // created anyway (`Media::Upload` has no way to know the picker went
    // away). Nothing references it, so it shows up under the Media
    // module's "Unused" filter, where it can be deleted (cleanup is manual
    // only, global constraints).
    this.uploads.abort()
    this.folderRequest?.abort()
    this.folderRequest = null
    this.folderItems = []
    this.chosenItems = []
    this.opening = null
    const opener = this.opener
    const detail = this.pending
    this.opener = null
    this.pending = null
    // The single opening's title is put back with the choice
    // (`admin--media--select#reset`, on the same close): Turbo's snapshot
    // keeps the dialog as it is left.
    this.multiple = false
    this.titleTarget.textContent = messages(this.element).t("components.ui.media_picker.title")
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

  // A finished upload: the counts follow it, the place it went to is said
  // with its digest now (`admin--media--live#uploaded`), and the first of the
  // batch is the selection -- selected, not chosen: the editor confirms. A
  // multiple opening is handed every one, in the order they finish (a
  // gallery adds what was just uploaded, up to what it takes).
  uploaded({ json, tile }) {
    updateCounts(json.counts, { picker: true, folders: json.folder_counts, tree: this.frameTarget.querySelector("#media-picker-folder-tree") })
    this.dispatch("digest", { detail: { place: json.place, digest: json.place_digest } })
    if (!(this.selectNextUpload || this.multiple) || !tile) return

    const raw = tile.querySelector("[data-admin--media--select-asset-param]")?.getAttribute("data-admin--media--select-asset-param")
    if (!raw) return

    this.selectNextUpload = false
    this.dispatch("uploaded", { detail: { payload: JSON.parse(raw) } })
  }
}
