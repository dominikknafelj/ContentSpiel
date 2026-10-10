import { Controller } from "@hotwired/stimulus"

// The shared tooltip (`Admin::Ui::TooltipComponent`, presence handoff 18):
// on the HOST, with the bubble inside it.
//
// - HOVER shows it after 300ms; KEYBOARD FOCUS shows it at once (a focus the
//   mouse gave shows nothing: the pointer is there already and has its own
//   rule). Moving from one host to another while a bubble shows, or just
//   after one went, switches at once: the wait is for the first, not for
//   reading along a row.
// - It goes when the pointer or the focus leaves, on ESCAPE (the focus stays
//   where it is, and nothing else is told about the key), and when the host
//   is PRESSED: what was pressed is acting now, and a bubble left over it
//   until the pointer moves hid what the press opened.
// - ITS PLACE is 6px under the host, centred, the stylesheet's. When that
//   would cross an edge it lines up with the host's edge on that side
//   instead (`data-align` on the bubble: "left" or "right"). The edge is the
//   window's, or that of a box around the host that clips what leaves it
//   (the media panel scrolls, and a bubble hanging out of it would be cut
//   and give it a scroll bar). Asked each time it is shown.
// - ONE AT A TIME: showing one hides the other.
//
// A bubble Turbo kept open in a snapshot is hidden again on connect.
const DELAY = 300
const SWITCH = 100
const MARGIN = 4

let showing = null
let wentAt = 0

export default class extends Controller {
  static targets = [ "bubble" ]

  connect() {
    this.escape = (event) => { if (event.key === "Escape") this.hide() }
    this.bubbleTarget.hidden = true
    this.bubbleTarget.removeAttribute("data-align")
  }

  disconnect() {
    this.hide()
  }

  // `mouseenter` on the host.
  enter() {
    if (this.pressed) return
    clearTimeout(this.timer)
    if (showing || Date.now() - wentAt < SWITCH) return this.show()
    this.timer = setTimeout(() => this.show(), DELAY)
  }

  // `focusin`: only the keyboard's.
  focus(event) {
    if (event.target.matches(":focus-visible")) this.show()
  }

  // `mouseleave` and `focusout`.
  leave() {
    this.pressed = false
    this.hide()
  }

  // `pointerdown` on the host: gone, and not back until the pointer has left.
  dismiss() {
    this.pressed = true
    this.hide()
  }

  show() {
    clearTimeout(this.timer)
    if (showing && showing !== this) showing.hide()
    this.bubbleTarget.hidden = false
    this.place()
    if (showing !== this) document.addEventListener("keydown", this.escape)
    showing = this
  }

  hide() {
    clearTimeout(this.timer)
    if (showing !== this) return
    this.bubbleTarget.hidden = true
    this.bubbleTarget.removeAttribute("data-align")
    document.removeEventListener("keydown", this.escape)
    showing = null
    wentAt = Date.now()
  }

  // Centred first, then measured: the side it crosses is the side it lines
  // up with.
  place() {
    const bubble = this.bubbleTarget
    bubble.removeAttribute("data-align")
    const box = bubble.getBoundingClientRect()
    const [ left, right ] = this.edges()
    if (box.left < left + MARGIN) bubble.setAttribute("data-align", "left")
    else if (box.right > right - MARGIN) bubble.setAttribute("data-align", "right")
  }

  // The window's left and right edge, narrowed by every box around the host
  // that does not show what overflows it.
  edges() {
    let left = 0
    let right = document.documentElement.clientWidth
    for (let box = this.element.parentElement; box && box !== document.body; box = box.parentElement) {
      if (getComputedStyle(box).overflowX === "visible") continue
      const rect = box.getBoundingClientRect()
      left = Math.max(left, rect.left)
      right = Math.min(right, rect.right)
    }
    return [ left, right ]
  }
}
