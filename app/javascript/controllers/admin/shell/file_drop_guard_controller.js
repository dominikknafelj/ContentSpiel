import { Controller } from "@hotwired/stimulus"

// A file dropped anywhere in CS Studio that is not a place for files must not
// replace the page (round 3, Task 9 M14). The browser's answer to a file
// dropped on a document is to NAVIGATE to it: the editor, with whatever it
// held unsaved, gone for a picture of the file that missed the drop zone by a
// few pixels. On <body>, for every screen.
//
// It only refuses: `dragover` over anything but a real target answers
// "none", and a `drop` there is cancelled. Real targets are left entirely
// alone -- a file drop zone (`file-drop`), a file input, anything editable (a
// rich-text editor takes its own drops), and the whole Media screen, whose
// `admin--media-drop` owns the window. A drag that carries no files (text, a
// link, SortableJS's pointer drags) is never touched.
export default class extends Controller {
  connect() {
    this.guard = (event) => {
      if (!Array.from(event.dataTransfer?.types || []).includes("Files")) return
      if (event.defaultPrevented || this.accepted(event.target)) return
      event.preventDefault()
      if (event.type === "dragover" && event.dataTransfer) event.dataTransfer.dropEffect = "none"
    }
    document.addEventListener("dragover", this.guard)
    document.addEventListener("drop", this.guard)
  }

  disconnect() {
    document.removeEventListener("dragover", this.guard)
    document.removeEventListener("drop", this.guard)
  }

  accepted(target) {
    if (document.querySelector("[data-controller~='admin--media-drop']")) return true
    if (!(target instanceof Element)) return false
    return target.closest("[data-controller~='file-drop'], input[type=file], [contenteditable]:not([contenteditable=false])") !== null
  }
}
