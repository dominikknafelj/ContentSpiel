import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// A GIF in CS Studio (`Admin::Ui::GifComponent`): a note's tile and the image
// viewer's stage. Its words are `components.ui.gif.*`, from the frame's
// `data-messages`.
//
// Without reduced motion this does nothing anyone sees: the picture plays,
// and the canvas and the button are not shown (the stylesheet's
// `motion-reduce:` and `motion-safe:` classes decide, not this script).
//
// WITH REDUCED MOTION the picture does not move by itself. It is in the page
// all the same, drawn invisible, so the frame has its shape; its first frame
// is painted on the canvas that lies over it (`paint`, when the picture has
// loaded -- drawing an animated image on a canvas draws its first frame), and
// a Play button stands in the middle. Play takes the canvas away and shows
// the picture; the button then reads Pause, with the Lucide `pause` for
// `play`, and Pause puts the still back. No server-made still: a note's file
// has no variants (decision D15).
//
// What is playing is said by the button (`data-playing`) and read from it,
// not kept here: a live refresh moves a note's tile into the redrawn thread
// (`admin--notes--live`), which connects this controller again, and a GIF
// someone set playing goes on playing. So nothing here that runs at a
// connect puts the still back: `srcValueChanged` acts only on an address
// that differs from the picture's, `gifValueChanged` only redraws the rules
// for the state the button says, and `disconnect` resets only a frame that
// has left the document (a moved frame is in the document again by the time
// Stimulus disconnects it).
//
// `src` is the one writer of the picture's address after the first render:
// the viewer steps by writing it, and each new address starts still. `gif`
// false is a picture that is no GIF on the viewer's stage: no canvas, no
// button, the picture shown whatever the motion setting.
export default class extends Controller {
  static targets = [ "moving", "still", "button", "label", "icon" ]
  static values = { src: String, gif: { type: Boolean, default: true } }

  connect() {
    this.paint()
  }

  disconnect() {
    if (!this.element.isConnected) this.stop()
  }

  // `turbo:before-cache@document`: the snapshot keeps the still, never a
  // playing GIF or a painted canvas (a canvas's pixels are not in a clone).
  cache() {
    this.stop()
  }

  get playing() {
    return this.buttonTarget.dataset.playing === "true"
  }

  srcValueChanged(value) {
    if (!this.hasMovingTarget) return
    const picture = this.movingTarget
    if ((picture.getAttribute("src") ?? "") === value) return

    if (value) picture.setAttribute("src", value)
    else picture.removeAttribute("src")
    this.stop()
  }

  // True again with the same address: the picture may have loaded while it
  // was false, when its `load` painted nothing, so the still is painted now.
  gifValueChanged(value) {
    if (!this.hasButtonTarget) return
    this.draw()
    if (value && !this.playing) this.paint()
  }

  // `load` on the picture, and on connect for one that was there already.
  // Only where it will be seen: a canvas the size of the picture is memory.
  paint() {
    const picture = this.movingTarget
    if (!this.gifValue || !window.matchMedia("(prefers-reduced-motion: reduce)").matches || !picture.complete || !picture.naturalWidth) return

    const canvas = this.stillTarget
    canvas.width = picture.naturalWidth
    canvas.height = picture.naturalHeight
    canvas.getContext("2d")?.drawImage(picture, 0, 0)
  }

  toggle() {
    this.buttonTarget.dataset.playing = String(!this.playing)
    this.draw()
    if (!this.playing) this.paint()
  }

  // The still back, not playing, and the canvas emptied (`width = 0` frees
  // its pixels); painted again when the picture is there to paint.
  stop() {
    this.buttonTarget.dataset.playing = "false"
    this.stillTarget.width = 0
    this.draw()
  }

  // The classes, the button's words and its icon for the state the button
  // says and the `gif` value.
  draw() {
    const playing = this.playing
    const gif = this.gifValue
    const words = messages(this.element)
    this.labelTarget.textContent = words.t(playing ? "components.ui.gif.pause" : "components.ui.gif.play")
    for (const icon of this.iconTarget.querySelectorAll("[data-gif-icon]")) icon.hidden = icon.dataset.gifIcon !== (playing ? "pause" : "play")
    this.buttonTarget.hidden = !gif
    this.stillTarget.hidden = !gif
    this.movingTarget.classList.toggle("motion-reduce:opacity-0", gif && !playing)
    this.stillTarget.classList.toggle("motion-reduce:block", !playing)
  }
}
