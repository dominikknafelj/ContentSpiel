import { Controller } from "@hotwired/stimulus"

// One toast (Admin::ToastComponent). Hides itself after `timeout` ms (0 =
// stays until dismissed); hovering or focusing pauses the clock so an Undo
// can't vanish under the pointer. At most three are shown: a fourth pushes
// the oldest out.
//
// A toast rendered outside the `#toasts` region (the flash of a redirect that
// answered a Turbo Frame request, which the layout renders inside the frame
// because only the frame's own content survives) is moved into it first.
export default class extends Controller {
  static values = { timeout: Number }

  connect() {
    const region = document.getElementById("toasts")
    if (region && !region.contains(this.element)) {
      // Re-parenting disconnects and reconnects this controller; the
      // reconnect is the one that carries on.
      region.append(this.element)
      return
    }

    const toasts = Array.from(this.element.parentElement.querySelectorAll(".admin-toast"))
    toasts.slice(0, Math.max(0, toasts.length - 3)).forEach((toast) => toast.remove())
    this.start()
  }

  disconnect() { this.pause() }

  start() {
    this.pause()
    if (this.timeoutValue > 0) this.timer = setTimeout(() => this.dismiss(), this.timeoutValue)
  }

  pause() { clearTimeout(this.timer) }

  dismiss() { this.element.remove() }
}
