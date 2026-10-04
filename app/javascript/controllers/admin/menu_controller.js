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

  // What keyboard navigation can land on: `.focus()` on a disabled button is a
  // no-op, so including one would leave ArrowDown stuck on the item before it
  // (a homepage's disabled "Move to trash" made the menu impossible to wrap).
  get focusableItems() { return this.items.filter((item) => !item.disabled) }

  get open() { return !this.panelTarget.hidden }

  toggle() { this.open ? this.close() : this.show() }

  show() {
    this.panelTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.focusableItems[0]?.focus()
  }

  close({ refocus = false } = {}) {
    this.panelTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
    if (refocus) this.buttonTarget.focus()
  }

  // A pick inside the panel (`close_on_select: true` wires this): the item has
  // done its job (opened a dialog, revealed a panel, followed a link), so the
  // panel goes. No refocus -- a dialog takes focus itself.
  select(event) {
    const item = event.target.closest("a, button")
    if (item && this.panelTarget.contains(item) && !item.disabled) this.close()
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
      const items = this.focusableItems
      if (items.length === 0) return
      const step = event.key === "ArrowDown" ? 1 : -1
      const index = items.indexOf(document.activeElement)
      items[(index + step + items.length) % items.length].focus()
    }
  }
}
