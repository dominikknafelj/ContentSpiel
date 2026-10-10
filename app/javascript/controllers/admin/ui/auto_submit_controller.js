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
// to cross the gap lives outside the instance: the id of the control that was
// focused when the submit fired (plus its caret, where it has one), restored
// in `connect` of the controller the new form gets -- when the new form has a
// control with that id.
//
// Any control is remembered, not just a text field: a number or date input
// reports `selectionStart` as null and a select has none at all, and leaving
// those out meant the audit log's "Subject id" lost focus after every pause
// and a keyboard user stepping through a select lost it on every option.
//
// What is remembered must not outlive its own reload. A submit that never
// renders (a network error, a navigation away in the meantime) would
// otherwise leave it lying around for the next filter form to connect --
// and the posts and media lists both call their search box `q`. So it names
// the form it belongs to (the action's path) and expires after
// `FOCUS_TTL` ms; a form somewhere else, or one connecting later, ignores it.
const FOCUS_TTL = 5000
let pendingFocus = null

export default class extends Controller {
  static values = { delay: { type: Number, default: 250 } }

  connect() {
    if (!pendingFocus) return

    const { id, start, end, path, at } = pendingFocus
    pendingFocus = null
    if (path !== this.path || Date.now() - at > FOCUS_TTL) return
    const field = this.element.querySelector(`#${CSS.escape(id)}`)
    if (!field) return

    field.focus()
    // Only a text-like input has a caret; `setSelectionRange` throws on the
    // others (and a select has no such method at all).
    try { if (start != null) field.setSelectionRange(start, end) } catch { /* no caret to restore */ }
  }

  // `event` is absent when `submitLater`'s timer calls this. A text field
  // that is removed while focused (the frame render replacing this form)
  // fires a last `change` from a detached element; that is the page
  // reloading, not the visitor choosing something, and acting on it would
  // submit a second time and wipe the focus just remembered.
  submit(event) {
    if (event?.target && !event.target.isConnected) return

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
    if (!field || !this.element.contains(field) || !field.id) return

    // `selectionStart` is a number only on text-like inputs: null on
    // number/date, undefined on a select. Reading it never throws.
    pendingFocus = { id: field.id, start: field.selectionStart, end: field.selectionEnd, path: this.path, at: Date.now() }
  }

  get path() { return new URL(this.element.action, window.location.href).pathname }
}
