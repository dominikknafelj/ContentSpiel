import { Controller } from "@hotwired/stimulus"

// Opens a <dialog> by id (Admin::DialogComponent). One instance on <body>
// serves every trigger on the page -- including ones Turbo streams in
// later -- so no view carries an inline `onclick="…showModal()"` (which a
// strict CSP would refuse anyway). Focus: the browser focuses the
// `autofocus` element if there is one (Cancel, on destructive dialogs),
// else the first focusable -- the dialog's × -- so we move it to the first
// form field when there is one.
export default class extends Controller {
  open(event) {
    const dialog = document.getElementById(event.params.id)
    if (!dialog || dialog.open) return
    event.preventDefault()
    dialog.showModal()
    if (dialog.querySelector("[autofocus]")) return
    const field = dialog.querySelector(".admin-dialog__body :is(input:not([type=hidden]), select, textarea)")
    if (field) field.focus()
  }

  // A click on the backdrop (the <dialog> element itself, outside its
  // content box) cancels, like Esc and ×.
  backdrop(event) {
    if (event.target instanceof HTMLDialogElement) event.target.close()
  }
}
