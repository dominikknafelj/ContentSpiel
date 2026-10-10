import { Controller } from "@hotwired/stimulus"

// A GIF in a note (notes spec §4.5 "Motion"; handoff "Inline image and still
// GIF tile"), on the tile `Admin::NotesScreen::FilesComponent` draws.
//
// Without reduced motion this does nothing anyone sees: the picture plays,
// and the canvas and the button are not shown (the stylesheet's
// `motion-reduce:` classes decide, not this script).
//
// WITH REDUCED MOTION the picture does not move by itself. It is in the page
// all the same, drawn invisible, so the tile has its shape; its first frame
// is painted on the canvas that lies over it (`paint`, when the picture has
// loaded -- drawing an animated image on a canvas draws its first frame), and
// a Play button stands in the middle. Play takes the canvas away and shows
// the picture; the button then reads Pause, and Pause puts the still back.
// No server-made still: a note's file has no variants (decision D15).
//
// What is playing is said by the button (`data-playing`) and read from it,
// not kept here: a live refresh moves the tile into the redrawn thread
// (`admin--notes--live`), which connects this controller again, and a GIF
// someone set playing goes on playing.
export default class extends Controller {
  static targets = [ "moving", "still", "button", "label", "icon" ]

  connect() {
    this.paint()
  }

  get playing() {
    return this.buttonTarget.dataset.playing === "true"
  }

  // `load` on the picture, and on connect for one that was there already.
  // Only where it will be seen: a canvas the size of the picture is memory.
  paint() {
    const picture = this.movingTarget
    if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches || !picture.complete || !picture.naturalWidth) return

    const canvas = this.stillTarget
    canvas.width = picture.naturalWidth
    canvas.height = picture.naturalHeight
    canvas.getContext("2d")?.drawImage(picture, 0, 0)
  }

  toggle() {
    const playing = !this.playing
    this.buttonTarget.dataset.playing = String(playing)
    this.labelTarget.textContent = playing ? this.buttonTarget.dataset.pause : this.buttonTarget.dataset.play
    this.iconTarget.hidden = playing
    this.movingTarget.classList.toggle("motion-reduce:opacity-0", !playing)
    this.stillTarget.classList.toggle("motion-reduce:block", !playing)
    if (!playing) this.paint()
  }
}
