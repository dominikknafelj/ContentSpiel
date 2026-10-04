import { Controller } from "@hotwired/stimulus"

// Filters apply as you change them (design pass spec §4, handoff §2.7): no
// Filter button. A select or checkbox submits at once; typing waits 250 ms
// so a search doesn't fire per keystroke. `requestSubmit` (not `submit`)
// so Turbo handles it like any other form.
//
// Focus survives the reload by hand rather than with `data-turbo-permanent`:
// a permanent element is kept *as is* across a render, so after "Clear"
// (a link to the unfiltered list, rendering a form whose search box is
// empty) the old element -- still holding the typed text -- would win. The
// frame render replaces this whole form, controller included, so what has
// to cross the gap lives outside the instance: the id and caret of the
// field that was focused when the submit fired, restored in `connect` of
// the controller the new form gets. Only a text field is restored (a select
// keeps no caret and refocusing it would re-open nothing useful), and only
// when the new form has a field with that id.
let pendingFocus = null

export default class extends Controller {
  static values = { delay: { type: Number, default: 250 } }

  connect() {
    if (!pendingFocus) return

    const { id, start, end } = pendingFocus
    pendingFocus = null
    const field = id && this.element.querySelector(`#${CSS.escape(id)}`)
    if (!field) return

    field.focus()
    try { field.setSelectionRange(start, end) } catch { /* not a text-like input */ }
  }

  submit() {
    clearTimeout(this.timer)
    this.rememberFocus()
    this.element.requestSubmit()
  }

  submitLater() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.submit(), this.delayValue)
  }

  disconnect() { clearTimeout(this.timer) }

  rememberFocus() {
    const field = document.activeElement
    const isText = field instanceof HTMLInputElement && typeof field.selectionStart === "number"
    pendingFocus = this.element.contains(field) && field.id && isText
      ? { id: field.id, start: field.selectionStart, end: field.selectionEnd }
      : null
  }
}
