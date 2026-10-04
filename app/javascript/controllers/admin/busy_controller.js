import { Controller } from "@hotwired/stimulus"

// A submit that takes a while (Settings' "Test connection"). While the Turbo
// submit is in flight the button is disabled, keeps the width it had (so the
// row doesn't jump when the label gets longer), and shows an 11px spinner
// with its `data-busy-label`; `turbo:submit-end` puts everything back.
export default class extends Controller {
  static targets = [ "button" ]

  connect() {
    this.element.addEventListener("turbo:submit-start", this.begin)
    this.element.addEventListener("turbo:submit-end", this.finish)
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-start", this.begin)
    this.element.removeEventListener("turbo:submit-end", this.finish)
  }

  begin = () => {
    const button = this.buttonTarget
    if (this.restore) return
    const { width, innerHTML } = { width: button.style.width, innerHTML: button.innerHTML }
    this.restore = () => {
      button.style.width = width
      button.innerHTML = innerHTML
      button.disabled = false
      this.restore = null
    }
    button.style.width = `${button.offsetWidth}px`
    button.disabled = true
    button.replaceChildren()
    const spinner = document.createElement("span")
    spinner.className = "admin-spinner"
    spinner.setAttribute("aria-hidden", "true")
    button.append(spinner, " ", button.dataset.busyLabel || "")
  }

  finish = () => { this.restore?.() }
}
