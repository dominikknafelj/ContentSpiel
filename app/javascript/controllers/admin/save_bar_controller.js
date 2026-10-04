import { Controller } from "@hotwired/stimulus"

// The explicit-save pattern for configuration screens (design pass spec §4,
// handoff §9 B12): the bar appears once something differs from what was
// loaded, counts the changed fields, and leaving with changes asks first.
// A change is counted per *named control*, comparing against a snapshot
// taken on connect -- so changing a field back removes it from the count.
//
// Leaving is guarded two ways: a Turbo visit (`turbo:before-visit`) opens the
// layout's one Leave dialog; a real unload (reload, closing the tab, a
// non-Turbo link) gets the browser's own prompt via `beforeunload`. A save
// (`turbo:submit-start`) clears the guard, since its redirect is a visit too.
// A save that fails re-renders the form with a fresh snapshot (the controller
// reconnects), so the guard is armed again by itself.
export default class extends Controller {
  static targets = ["bar", "count"]

  connect() {
    this.initial = this.snapshot()
    this.submitting = false
    this.leaving = false
    this.onVisit = (event) => this.guard(event)
    this.onUnload = (event) => { if (this.changes > 0 && !this.submitting) event.preventDefault() }
    document.addEventListener("turbo:before-visit", this.onVisit)
    window.addEventListener("beforeunload", this.onUnload)
    this.refresh()
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.onVisit)
    window.removeEventListener("beforeunload", this.onUnload)
    this.clearPendingLeave()
  }

  refresh() {
    const count = this.changes
    this.barTarget.hidden = count === 0
    this.countTarget.textContent = count === 0 ? "" : count === 1 ? "1 unsaved change" : `${count} unsaved changes`
  }

  markSubmitting() { this.submitting = true }

  guard(event) {
    if (this.changes === 0 || this.submitting || this.leaving) return
    event.preventDefault()
    const dialog = document.getElementById("leave-dialog")
    const confirm = dialog.querySelector("[data-leave-confirm]")
    // A listener, not `onclick =`, and `once`: opening the dialog repeatedly
    // (Stay, then click another link) must not stack handlers that would each
    // fire a visit. A previous, never-used one is removed before a new one is
    // armed, and again if the dialog is dismissed without Leave.
    this.clearPendingLeave()
    const url = event.detail.url
    this.pendingLeave = { dialog, confirm, handler: () => {
      this.leaving = true
      dialog.close()
      window.Turbo.visit(url)
    } }
    confirm.addEventListener("click", this.pendingLeave.handler, { once: true })
    this.pendingLeave.onClose = () => this.clearPendingLeave()
    dialog.addEventListener("close", this.pendingLeave.onClose, { once: true })
    dialog.showModal()
  }

  clearPendingLeave() {
    if (!this.pendingLeave) return
    const { dialog, confirm, handler, onClose } = this.pendingLeave
    confirm.removeEventListener("click", handler)
    dialog.removeEventListener("close", onClose)
    this.pendingLeave = null
  }

  snapshot() {
    const values = {}
    for (const field of this.element.elements) {
      if (!field.name || field.type === "hidden" || field.type === "submit") continue
      const toggle = field.type === "checkbox" || field.type === "radio"
      const key = toggle ? `${field.name}=${field.value}` : field.name
      values[key] = toggle ? String(field.checked) : field.value
    }
    return values
  }

  get changes() {
    const now = this.snapshot()
    return Object.keys({ ...this.initial, ...now }).filter((key) => this.initial[key] !== now[key]).length
  }
}
