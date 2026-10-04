import { Controller } from "@hotwired/stimulus"

// A popover menu (Admin::MenuComponent). The button toggles the panel;
// opening focuses the first item, ArrowDown/ArrowUp move between the panel's
// links and buttons, Escape closes and hands focus back to the button, and a
// click anywhere outside closes it.
export default class extends Controller {
  static targets = [ "button", "panel" ]

  connect() {
    this.items.forEach((item) => item.setAttribute("role", "menuitem"))
  }

  get items() { return Array.from(this.panelTarget.querySelectorAll("a, button")) }

  get open() { return !this.panelTarget.hidden }

  toggle() { this.open ? this.close() : this.show() }

  show() {
    this.panelTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.items[0]?.focus()
  }

  close({ refocus = false } = {}) {
    this.panelTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
    if (refocus) this.buttonTarget.focus()
  }

  closeOutside(event) {
    if (this.open && !this.element.contains(event.target)) this.close()
  }

  keydown(event) {
    if (!this.open) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.close({ refocus: true })
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      const items = this.items
      if (items.length === 0) return
      const step = event.key === "ArrowDown" ? 1 : -1
      const index = items.indexOf(document.activeElement)
      items[(index + step + items.length) % items.length].focus()
    }
  }
}
