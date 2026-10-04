import { Controller } from "@hotwired/stimulus"

// One toast (Admin::ToastComponent). Hides itself after `timeout` ms (0 =
// stays until dismissed); hovering or focusing pauses the clock so an Undo
// can't vanish under the pointer. At most three are shown: a fourth pushes
// the oldest out.
//
// A toast rendered outside the `#toasts` region (the flash of a redirect that
// answered a Turbo Frame request, which the layout renders inside the frame
// because only the frame's own content survives) is moved into it first.
//
// A toast never comes back from Turbo's page cache. Turbo snapshots a page as
// it leaves it and renders that snapshot again on Back (and as the preview of
// a forward visit); a toast on screen at that moment would return with it --
// an Undo whose target may be long gone, an error that has since been fixed
// -- and its clock would start over. So a render that comes out of the cache
// has its toasts taken out before it reaches the page.
//
// Deliberately NOT `data-turbo-temporary`, the stock way to keep an element
// out of the cache: Turbo implements that by removing the element from the
// *live* page on `turbo:before-cache`, and promoting a frame navigation to a
// history entry (`data-turbo-action="advance"` on `#content`) caches a
// snapshot too, with the page staying where it is. The toast a frame
// response had just relayed ("Group saved", "Draft created") was deleted the
// moment it appeared.
//
// "From the cache" is: a preview (`data-turbo-preview` on <html>, set before
// `turbo:before-render` fires), or a restoration visit (Back/Forward --
// `turbo:visit` names its action). A restoration that misses the cache
// renders a fresh response, which is stripped just the same; no flash can be
// riding on a Back, so nothing is lost. The listeners are document-level and
// installed once, when this module first loads.
let restoring = false
document.addEventListener("turbo:visit", (event) => { restoring = event.detail.action === "restore" })
document.addEventListener("turbo:before-render", (event) => {
  if (!restoring && !document.documentElement.hasAttribute("data-turbo-preview")) return
  event.detail.newBody.querySelectorAll(".admin-toast").forEach((toast) => toast.remove())
})

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
