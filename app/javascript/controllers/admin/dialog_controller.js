import { Controller } from "@hotwired/stimulus"

// Opens a <dialog> by id (Admin::DialogComponent). One instance on <body>
// serves every trigger on the page -- including ones Turbo streams in
// later -- so no view carries an inline `onclick="…showModal()"` (which a
// strict CSP would refuse anyway). Focus: the browser focuses the
// `autofocus` element if there is one (Cancel, on destructive dialogs),
// else the first focusable -- the dialog's × -- so we move it to the first
// form field when there is one.
export default class extends Controller {
  // A server-requested dialog (`data-admin--dialog-open-on-load`, a form
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
    document.querySelectorAll("dialog[data-admin--dialog-open-on-load]").forEach((dialog) => {
      dialog.removeAttribute("data-admin--dialog-open-on-load")
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
    dialog.showModal()
    this.focusFirstField(dialog)
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
