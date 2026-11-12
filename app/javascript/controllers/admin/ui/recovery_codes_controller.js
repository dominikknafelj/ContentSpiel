import { Controller } from "@hotwired/stimulus"

// The recovery codes block (`Admin::Ui::RecoveryCodesComponent`): the codes
// are the copy box's text and stand nowhere else, so this reads them from
// there and keeps no copy.
//
// - `toggle` enables Done (a button, or the page frame's link through
//   `aria-disabled`) only while the box is ticked.
// - `refuse` stops a click on the disabled link.
// - `download` saves the box's text as `recovery-codes.txt`, from a Blob made
//   in the browser: no address of the server carries the codes.
// - At `turbo:before-cache` and `pagehide` the box's text is emptied and the
//   block removed, so neither Turbo's snapshot nor the back/forward cache
//   keeps the codes. In the dialog frame the dialog's `close` (Done or
//   Escape; the event does not bubble, so it is heard in the capture phase)
//   forgets them the same way, as the page stays open after it.
// - A checkbox the browser restored as ticked enables Done on connect.
export default class extends Controller {
  static targets = ["list", "saved", "done", "block"]

  connect() {
    this.forget = () => {
      this.listTargets.forEach((element) => { element.textContent = "" })
      this.blockTargets.forEach((element) => element.remove())
    }
    this.element.addEventListener("close", this.forget, true)
    document.addEventListener("turbo:before-cache", this.forget)
    window.addEventListener("pagehide", this.forget)
    this.toggle()
  }

  disconnect() {
    this.element.removeEventListener("close", this.forget, true)
    document.removeEventListener("turbo:before-cache", this.forget)
    window.removeEventListener("pagehide", this.forget)
  }

  toggle() {
    const ready = this.savedTarget.checked
    if (this.doneTarget.tagName === "A") {
      this.doneTarget.setAttribute("aria-disabled", String(!ready))
    } else {
      this.doneTarget.disabled = !ready
    }
  }

  refuse(event) {
    if (this.doneTarget.getAttribute("aria-disabled") === "true") event.preventDefault()
  }

  download(event) {
    event.preventDefault()
    const blob = new Blob([`${this.listTarget.textContent.trim()}\n`], { type: "text/plain" })
    const url = URL.createObjectURL(blob)
    const link = document.createElement("a")
    link.href = url
    link.download = "recovery-codes.txt"
    document.body.appendChild(link)
    link.click()
    link.remove()
    setTimeout(() => URL.revokeObjectURL(url), 0)
  }
}
