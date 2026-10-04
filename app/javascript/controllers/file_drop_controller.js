import { Controller } from "@hotwired/stimulus"

// Behaviour for `Admin::FileDropComponent`: highlight the zone while a file is
// dragged over it, hand a dropped file to the hidden input (and fire its
// `change`, which is what whoever owns the upload listens to), and echo the
// chosen name(s) into the polite live region.
//
// `drop` stops propagation on purpose: the media screen wraps this zone in its
// own `admin--media-upload` element that also handles `drop` (for drops
// outside the zone). Without the stop, a drop inside the zone would reach both
// -- once through our synthetic `change`, once through that handler -- and
// upload every file twice.
export default class extends Controller {
  static targets = [ "input", "name" ]

  dragOver(event) {
    // Only a drag carrying files is ours; preventDefault is what tells the
    // browser this element accepts a drop at all.
    if (!this.carriesFiles(event)) return
    event.preventDefault()
    this.element.dataset.dragging = ""
  }

  dragLeave(event) {
    // dragleave also fires when moving onto a child; only clear on a real exit.
    if (event.relatedTarget && this.element.contains(event.relatedTarget)) return
    delete this.element.dataset.dragging
  }

  drop(event) {
    if (!this.carriesFiles(event)) return
    event.preventDefault()
    event.stopPropagation()
    delete this.element.dataset.dragging

    const files = event.dataTransfer.files
    if (!files || files.length === 0) return

    // A single-file input must not receive several files.
    this.inputTarget.files = this.inputTarget.multiple || files.length === 1 ? files : this.firstOnly(files)
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  changed() {
    // An empty list (the upload owner cleared the input right after `change`,
    // as admin--media-upload does) leaves the previous text alone rather than
    // blanking it.
    const files = Array.from(this.inputTarget.files || [])
    if (files.length === 0) return
    this.nameTarget.textContent = files.length > 1 ? `${files.length} files` : files[0].name
  }

  carriesFiles(event) {
    return Array.from(event.dataTransfer?.types || []).includes("Files")
  }

  firstOnly(files) {
    const transfer = new DataTransfer()
    transfer.items.add(files[0])
    return transfer.files
  }
}
