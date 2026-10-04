import { Controller } from "@hotwired/stimulus"

// The explicit-save pattern for configuration screens (design pass spec §4,
// handoff §9 B12): the form's footer (Save, Cancel) is always there, counts
// the changed fields, and leaving with changes asks first. Save is disabled
// while an existing record has nothing to save.
// A change is counted per *named control* (per group name for radios),
// comparing against a snapshot taken on connect -- so changing a field back
// removes it from the count.
//
// Two server-driven states sit on top of the snapshot count:
//   dirty  -- the server re-rendered the form with errors (a 422). The
//             re-render reconnects this controller, whose snapshot is then the
//             typed, invalid values (count 0); `dirty` keeps Save enabled and
//             the leave guard up regardless, since nothing was saved.
//   always -- Save is enabled even with nothing changed (a new record: the
//             form's whole point is to be submitted). The guard still waits
//             for a real change.
//
// The guard is page-level, not per form: the account screen has two of these
// forms, and each asking separately would prompt twice. One document listener
// (shared by every connected instance) asks "is any form unsaved and not the
// one being submitted?" and opens the single Leave dialog.
const instances = new Set()
const shared = { leaving: false, pending: null }

function onVisit(event) {
  if (shared.leaving) return
  if (![...instances].some((instance) => instance.unsaved && !instance.submitting)) return
  event.preventDefault()
  openLeaveDialog(event.detail.url)
}

function onUnload(event) {
  if ([...instances].some((instance) => instance.unsaved && !instance.submitting)) event.preventDefault()
}

function openLeaveDialog(url) {
  const dialog = document.getElementById("leave-dialog")
  const confirm = dialog.querySelector("[data-leave-confirm]")
  // A listener, not `onclick =`, and `once`: opening the dialog repeatedly
  // (Stay, then click another link) must not stack handlers that would each
  // fire a visit. A previous, never-used one is removed before a new one is
  // armed, and again if the dialog is dismissed without Leave.
  clearPendingLeave()
  const handler = () => {
    shared.leaving = true
    dialog.close()
    window.Turbo.visit(url)
  }
  const onClose = () => clearPendingLeave()
  shared.pending = { dialog, confirm, handler, onClose }
  confirm.addEventListener("click", handler, { once: true })
  dialog.addEventListener("close", onClose, { once: true })
  dialog.showModal()
}

function clearPendingLeave() {
  if (!shared.pending) return
  const { dialog, confirm, handler, onClose } = shared.pending
  confirm.removeEventListener("click", handler)
  dialog.removeEventListener("close", onClose)
  shared.pending = null
}

export default class extends Controller {
  static targets = ["bar", "count", "save"]
  static values = { dirty: Boolean, always: Boolean }

  connect() {
    this.initial = this.snapshot()
    this.submitting = false
    if (instances.size === 0) {
      document.addEventListener("turbo:before-visit", onVisit)
      window.addEventListener("beforeunload", onUnload)
    }
    instances.add(this)
    shared.leaving = false
    this.refresh()
  }

  disconnect() {
    instances.delete(this)
    if (instances.size === 0) {
      document.removeEventListener("turbo:before-visit", onVisit)
      window.removeEventListener("beforeunload", onUnload)
      clearPendingLeave()
    }
  }

  refresh() {
    const count = this.changes
    // A Save that the password field already governs (`data-password-submit`:
    // disabled until the password is long enough) is left to it -- two
    // controllers writing one button's `disabled` on the same keystroke would
    // undo each other, and such a form can't be saved with nothing typed
    // anyway.
    if (this.hasSaveTarget && !("passwordSubmit" in this.saveTarget.dataset)) {
      this.saveTarget.disabled = !(this.unsaved || this.alwaysValue)
    }
    this.countTarget.textContent = count > 0
      ? (count === 1 ? "1 unsaved change" : `${count} unsaved changes`)
      : (this.unsaved ? "Unsaved changes" : (this.alwaysValue ? "" : "No unsaved changes"))
  }

  markSubmitting() { this.submitting = true }

  // A submit that didn't go through (a 422 re-renders and reconnects anyway;
  // a network error or an abort leaves this form in place): the form is
  // unsaved again, so leaving must ask again.
  submitEnded(event) {
    if (!event.detail.success) this.submitting = false
  }

  get unsaved() { return this.dirtyValue || this.changes > 0 }

  // What the form would SUBMIT, not what its controls look like: a disabled
  // control and an unticked checkbox are both simply absent. That matters
  // because other controllers inside the form adjust controls on connect --
  // `admin--branch-picker` ticks and disables every box under a chosen
  // branch -- and on a Turbo frame navigation this controller connects (and
  // takes its baseline) *before* they run. Recording a checkbox's `checked`
  // as such made an untouched group form count "1 unsaved change" and ask
  // before leaving; a box that is ticked-and-disabled submits exactly what an
  // unticked one does, so baseline and later snapshots now agree whatever the
  // connect order.
  snapshot() {
    const values = {}
    for (const field of this.element.elements) {
      if (!field.name || field.disabled || field.type === "hidden" || field.type === "submit") continue
      if (field.type === "radio") {
        // One value per group: flipping a radio is one change, not two.
        if (field.checked) values[field.name] = field.value
        else values[field.name] ??= ""
      } else if (field.type === "checkbox") {
        if (field.checked) values[`${field.name}=${field.value}`] = "on"
      } else {
        values[field.name] = field.value
      }
    }
    return values
  }

  get changes() {
    const now = this.snapshot()
    return Object.keys({ ...this.initial, ...now }).filter((key) => this.initial[key] !== now[key]).length
  }
}
