import { Controller } from "@hotwired/stimulus"

// A popover menu (Admin::Ui::MenuComponent). The button toggles the panel;
// opening focuses the first item, ArrowDown/ArrowUp move between the panel's
// links and buttons, Escape closes and hands focus back to the button, and a
// click anywhere outside closes it. A LIST panel (`list: true`) has nothing
// to pick: pressing its button moves the focus into the list as a whole
// (`enter`), something inside the button may show it on hover (`reveal`),
// and it closes when neither the pointer nor the focus is on it (`leave`).
export default class extends Controller {
  static targets = [ "button", "panel" ]

  connect() {
    this.items.forEach((item) => item.setAttribute("role", "menuitem"))
  }

  // A menu that leaves the document, or is moved in it, is closed. A pick
  // normally closes its menu from the panel's own click listener (`select`),
  // but an item may move the very element the menu is in -- a block card's or
  // a section's "Move up" puts the card before its neighbour -- and Stimulus
  // then unbinds this controller's listeners before the click has bubbled
  // from the item to the panel. Nothing closed the menu: it came back
  // connected and still open, over the card it had moved. Closing here needs
  // no listener, and a menu Turbo keeps in a snapshot is a closed one too.
  disconnect() {
    this.close()
  }

  get items() { return Array.from(this.panelTarget.querySelectorAll("a, button")) }

  // What keyboard navigation can land on: `.focus()` on a disabled button is a
  // no-op, so including one would leave ArrowDown stuck on the item before it
  // (a homepage's disabled "Move to trash" made the menu impossible to wrap).
  get focusableItems() { return this.items.filter((item) => !item.disabled) }

  get open() { return !this.panelTarget.hidden }

  // Whether a list panel was entered by a press of its button. Kept on the
  // element and not in this object: whoever replaces the menu under an open
  // list someone is reading (presence's people are redrawn when they
  // change) says so on the new element, and the next press then closes the
  // list as it would have.
  get entered() { return this.element.hasAttribute("data-entered") }
  set entered(value) { this.element.toggleAttribute("data-entered", value) }

  toggle() { this.open ? this.close() : this.show() }

  show() {
    this.panelTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.focusableItems[0]?.focus()
  }

  close({ refocus = false } = {}) {
    this.entered = false
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

  // A list panel, shown and nothing else: the focus stays where it is.
  reveal() {
    this.panelTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
  }

  // A list panel's button, pressed: the list is shown and takes the focus,
  // so a screen reader reads it through; pressed again while the list has
  // the focus, it closes and the button has the focus back.
  // (`entered`: the press itself takes the focus out of the list, so where
  // the focus is by then says nothing.)
  enter() {
    if (this.open && this.entered) return this.close({ refocus: true })
    this.reveal()
    this.entered = true
    this.panelTarget.focus()
  }

  // A list panel: the pointer or the focus has left. It closes when NEITHER is on it any more -- a
  // keyboard user's list does not go because the mouse moved, nor a mouse
  // user's because the focus went elsewhere. When the pointer leaves, the
  // focus counts only INSIDE THE LIST: on the button it says nothing about
  // the list (it stays there after a press that closed one), and a list
  // shown by hover would never close again.
  leave(event) {
    const focused = event.type === "focusout" ? this.element.contains(event.relatedTarget) : this.panelTarget.contains(document.activeElement)
    const hovered = event.type === "mouseleave" ? false : this.element.matches(":hover")
    if (!focused && !hovered) this.close()
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
