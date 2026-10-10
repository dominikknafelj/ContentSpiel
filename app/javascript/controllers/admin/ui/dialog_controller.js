import { Controller } from "@hotwired/stimulus"

// Opens a <dialog> by id (Admin::Ui::DialogComponent). One instance on <body>
// serves every trigger on the page -- including ones Turbo streams in
// later -- so no view carries an inline `onclick="…showModal()"` (which a
// strict CSP would refuse anyway). Focus: the browser focuses the
// `autofocus` element if there is one (Cancel, on destructive dialogs),
// else the first focusable -- the dialog's × -- so we move it to the first
// form field when there is one.
//
// Focus on the way back: the browser returns it to whatever had it before
// `showModal()`. When that was an item of a menu (`Admin::Ui::MenuComponent` --
// the block card's "Delete block…", the editor header's Schedule… /
// Unpublish / Move to trash, a list row's Move to trash), the menu has
// closed on the pick and the item is hidden, so focus fell to <body>: a
// keyboard user was sent back to the top of the page. `open` therefore
// remembers the menu's own button and `returnFocus` gives it focus when the
// dialog closes with focus on nothing.
export default class extends Controller {
  // A server-requested dialog (`data-admin--ui--dialog-open-on-load`, a form
  // dialog reopened with its error after a refused submit). The controller
  // lives on <body>, which Turbo Drive keeps across visits, so `connect` only
  // covers a full load; `turbo:load` covers every visit. Turbo's cache
  // snapshots would otherwise carry the attribute along, so it is stripped
  // the moment the dialog opens: Back never reopens it.
  connect() {
    this.openOnLoad = () => this.openRequested()
    document.addEventListener("turbo:load", this.openOnLoad)
    this.openRequested()
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.openOnLoad)
  }

  openRequested() {
    document.querySelectorAll("dialog[data-admin--ui--dialog-open-on-load]").forEach((dialog) => {
      dialog.removeAttribute("data-admin--ui--dialog-open-on-load")
      if (dialog.open) return
      dialog.showModal()
      this.focusFirstField(dialog)
    })
  }

  focusFirstField(dialog) {
    if (dialog.querySelector("[autofocus]")) return
    const field = dialog.querySelector(".admin-dialog__body :is(input:not([type=hidden]), select, textarea)")
    if (field) field.focus()
  }

  open(event) {
    const dialog = document.getElementById(event.params.id)
    if (!dialog || dialog.open) return
    event.preventDefault()
    // Tells a form dialog who opened it, so it can preset itself from the
    // trigger's own `data-*` (`admin--editor--new-record`: Inside and Title).
    // Dispatched on <body>, bubbling to `document`, before the dialog shows.
    this.dispatch("opening", { detail: { dialog, trigger: event.currentTarget } })
    this.returnFocus(dialog, event.currentTarget)
    dialog.showModal()
    this.focusFirstField(dialog)
  }

  // See the class comment. Only for a trigger inside a menu's panel, only
  // once, and only when the close left focus nowhere (a dialog whose action
  // replaced the page or removed the card has nothing to return to, and one
  // that handed focus on itself is left alone).
  returnFocus(dialog, trigger) {
    const button = trigger.closest?.("[role=menu]")?.closest("[data-controller~='admin--ui--menu']")?.querySelector("[data-admin--ui--menu-target='button']")
    if (!button) return

    // As `close` fires, focus has not reached <body> yet: the item it should
    // go back to cannot take it, so it is still on an element that is no
    // longer drawn (the closed dialog's own button, in Chrome) until the
    // browser's next rendering step. An element with no box counts as lost.
    dialog.addEventListener("close", () => {
      const active = document.activeElement
      const lost = !active || active === document.body || active.getClientRects().length === 0
      if (lost && button.isConnected) button.focus()
    }, { once: true })
  }

  // `click` fires on the nearest common ancestor of the mousedown and
  // mouseup targets, and a dialog's backdrop belongs to the <dialog>
  // element itself -- so dragging a text selection from inside the dialog
  // out onto the backdrop would "click" the <dialog> and close it,
  // losing whatever was typed in a form dialog. Remember where the press
  // started and close only when both ends landed on the dialog element.
  remember(event) {
    this.pressTarget = event.target
  }

  // A click on the backdrop (the <dialog> element itself, outside its
  // content box) cancels, like Esc and ×.
  backdrop(event) {
    const pressed = this.pressTarget
    this.pressTarget = null
    if (event.target instanceof HTMLDialogElement && pressed === event.target) event.target.close()
  }
}
