import { Controller } from "@hotwired/stimulus"

// The explicit-save pattern for configuration screens (design pass spec §4,
// handoff §9 B12): the bar appears once something differs from what was
// loaded, counts the changed fields, and leaving with changes asks first.
// A change is counted per *named control* (per group name for radios),
// comparing against a snapshot taken on connect -- so changing a field back
// removes it from the count.
//
// Two server-driven states sit on top of the snapshot count:
//   dirty  -- the server re-rendered the form with errors (a 422). The
//             re-render reconnects this controller, whose snapshot is then the
//             typed, invalid values (count 0); `dirty` keeps the bar and the
//             leave guard up regardless, since nothing was saved.
//   always -- the bar is visible even with nothing changed (a new record, whose
//             only submit button is the bar's Save). The guard still waits for
//             a real change.
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

// Visible bars stack from the bottom in document order, so two dirty forms'
// sticky bars never cover each other: the last one sits at the bottom, each
// earlier one above the bars after it.
function layoutBars() {
  const visible = [...instances].map((instance) => instance.barTarget).filter((bar) => !bar.hidden)
  visible.sort((a, b) => (a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1))
  let offset = 0
  for (const bar of visible.reverse()) {
    bar.style.bottom = `${offset}px`
    offset += bar.offsetHeight
  }
}

export default class extends Controller {
  static targets = ["bar", "count"]
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
    layoutBars()
  }

  refresh() {
    const count = this.changes
    this.barTarget.hidden = !(this.unsaved || this.alwaysValue)
    this.countTarget.textContent = count > 0
      ? (count === 1 ? "1 unsaved change" : `${count} unsaved changes`)
      : (this.unsaved ? "Unsaved changes" : "")
    layoutBars()
  }

  markSubmitting() { this.submitting = true }

  // A submit that didn't go through (a 422 re-renders and reconnects anyway;
  // a network error or an abort leaves this form in place): the form is
  // unsaved again, so leaving must ask again.
  submitEnded(event) {
    if (!event.detail.success) this.submitting = false
  }

  get unsaved() { return this.dirtyValue || this.changes > 0 }

  snapshot() {
    const values = {}
    for (const field of this.element.elements) {
      if (!field.name || field.type === "hidden" || field.type === "submit") continue
      if (field.type === "radio") {
        // One value per group: flipping a radio is one change, not two.
        if (field.checked) values[field.name] = field.value
        else values[field.name] ??= ""
      } else if (field.type === "checkbox") {
        values[`${field.name}=${field.value}`] = String(field.checked)
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
