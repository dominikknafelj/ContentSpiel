import { Controller } from "@hotwired/stimulus"
import { UploadTiles, updateCounts } from "media/upload_tiles"

// The Media module's own multi-file upload (media library design spec §6, round 3
// Task 9): files dropped anywhere on the screen (`admin--media-drop`, which hands
// them over as `admin--media-drop:dropped`), the header's "Upload images" button
// and the plain file input in the drop zone -- all three end in `#upload`, which
// gives every file a progress tile at the start of the grid and sends them one at
// a time, one POST per file, to `Admin::MediaController#create`. That is what
// keeps one refused or oversized file (an SVG, something over 10 MB) from blocking
// its siblings: it keeps its own tile with the server's reason and Dismiss, and
// the others become real tiles. There is no browser `alert()`/`confirm()` here
// (spec: "no browser dialogs") and, since this round, no reload: the answer carries
// the finished tile and the new counts (`media/upload_tiles.js`), so an upload that
// ends while an editor is typing in the side panel changes nothing under them.
//
// The queue is module-level, not per controller: choosing a tile is a frame
// navigation that replaces this very element, and a file still going up (or a
// refused one's tile) must outlive that. The next instance takes the queue over
// (`connect`) and puts the live tiles back at the start of the new grid.
let tiles = null

export default class extends Controller {
  static targets = [ "input", "status" ]
  static values = { url: String }

  connect() {
    if (!tiles) {
      tiles = new UploadTiles({ url: this.urlValue, grid: () => this.grid, fields: () => this.fields, onUploaded: (done) => this.uploaded(done), announce: (text) => this.announce(text) })
    }
    // This page's callbacks (its own status region, its own URL), the same queue.
    Object.assign(tiles, { url: this.urlValue, grid: () => this.grid, fields: () => this.fields, announce: (text) => this.announce(text), onUploaded: (done) => this.uploaded(done) })
    tiles.reattach()
  }

  // The header's "Upload images" button: the same file input the drop zone wraps,
  // so one path -- `filesSelected` -- handles both.
  browse() {
    this.inputTarget.click()
  }

  filesSelected() {
    this.upload(Array.from(this.inputTarget.files))
    // Cleared immediately: re-picking the exact same file a second time wouldn't
    // otherwise fire another `change` event at all, since the input's own value
    // hasn't changed from the browser's point of view.
    this.inputTarget.value = ""
  }

  dropped(event) {
    this.upload(Array.from(event.detail?.files || []))
  }

  upload(files) {
    if (files.length > 0) tiles.add(files)
  }

  // The grid on the screen now. The picker's own grid (a `ul` in a dialog in the
  // layout) is not it.
  get grid() {
    return document.querySelector("#content ul.admin-media-grid")
  }

  // The search the grid is showing, so the counts that come back are for it.
  get fields() {
    const q = document.querySelector("#content input[type=search][name=q]")?.value
    return q ? { q } : {}
  }

  uploaded({ json }) {
    updateCounts(json.counts)
  }

  announce(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
