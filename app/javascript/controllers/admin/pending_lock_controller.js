import { Controller } from "@hotwired/stimulus"

// Instant actions wait for pending changes (design pass round 3, decision
// D10). An explicit-save screen also has actions that happen at once -- Add
// language, Turn off, Test connection, Save key -- and each answers by
// re-rendering the screen, which would throw away whatever the main form
// holds unsaved. So while any `admin--save-bar` form on the page is unsaved,
// every `control` target inside this element is disabled and the `hint`
// target says why: "Save or cancel your changes first." Both revert the
// moment the form is clean again (saved, cancelled, or typed back).
//
//   <div data-controller="admin--pending-lock">
//     <button data-admin--pending-lock-target="control">Test connection</button>
//     <p data-admin--pending-lock-target="hint" hidden></p>
//   </div>
//
// It knows the forms only through `admin--save-bar:state` on `document`
// (`detail.unsaved`, for the whole page). The forms may have announced
// themselves before this controller connected -- each controller arrives by
// its own dynamic import, and a form re-rendered with errors is unsaved from
// the start -- so on connect it asks for the state once
// (`admin--save-bar:query`, which `admin--save-bar` answers). With no
// such form on the page nobody answers and nothing is locked.
//
// A button, input or select is `disabled`. A link can't be: it gets
// `aria-disabled="true"` and its click is swallowed here, in the capture
// phase and before Turbo or any `data-action` on the link sees it (Turbo
// ignores a click that is already cancelled). A control that was disabled
// for its own reasons is never touched, so unlocking doesn't enable it.
//
// A `control` target must be a button, a link, or a control of ANOTHER form
// (an instant action's own). A NAMED control of an explicit-save form is
// never locked: disabled, it drops out of what that form submits, the footer
// counts that as a change, and the lock it caused would keep itself locked
// for good. (An unnamed button inside that form -- a dialog's trigger -- is
// no part of what it submits, and is locked like any other.) That includes a
// named `type="button"`, which looks like an action but is in the form's
// `elements` like a field: it is skipped too, with a warning in the console
// naming it.
//
// ONE EXEMPTION (final wave B round 2, N3). Something typed BESIDE the form
// that the form's Save would drop holds that Save back (`admin--save-bar`,
// `data-save-bar-holds` -- Settings' API key entry). Locking the entry too,
// because the form has changes, left the two locking each other: the footer
// said "Save or cancel the API key first." and the key's own Save said "Save
// or cancel your changes first.". So a control inside an element that carries
// `data-save-bar-holds` is never locked -- that is the way out the footer's
// sentence names -- and a hint beside it is not shown. Safe only because that
// action's answer keeps the form's fields (the key write answers with streams
// and follows the carried-base rule). The holder announces every change of
// its state with `admin--save-bar:query`, which brings a fresh `state` here.
const HINT = "Save or cancel your changes first."
const MARK = "data-pending-locked"
const warned = new WeakSet()

export default class extends Controller {
  static targets = ["control", "hint"]

  connect() {
    this.locked = false
    this.onState = (event) => this.apply(Boolean(event.detail?.unsaved))
    this.swallow = (event) => {
      if (!this.locked) return
      const link = event.target instanceof Element && event.target.closest("a")
      if (!link || !this.controlTargets.includes(link)) return
      event.preventDefault()
      event.stopPropagation()
    }
    document.addEventListener("admin--save-bar:state", this.onState)
    this.element.addEventListener("click", this.swallow, true)
    this.apply(false)
    document.dispatchEvent(new CustomEvent("admin--save-bar:query"))
  }

  disconnect() {
    document.removeEventListener("admin--save-bar:state", this.onState)
    this.element.removeEventListener("click", this.swallow, true)
  }

  // A control streamed in while locked is locked too.
  controlTargetConnected(control) {
    if (this.locked && !this.exempt(control)) this.lock(control)
  }

  // So is a hint: the key component a write's answer replaces carries its own
  // (targets of the first render connect before `connect()`; `apply` there
  // covers them).
  hintTargetConnected(hint) {
    if (this.locked === undefined) return
    if (!hint.textContent.trim()) hint.textContent = HINT
    hint.hidden = !this.locked || this.besideHolder(hint)
  }

  // See "ONE EXEMPTION".
  exempt(control) { return control.closest("[data-save-bar-holds]") !== null }

  besideHolder(hint) { return hint.parentElement?.querySelector("[data-save-bar-holds]") != null }

  apply(locked) {
    this.locked = locked
    this.controlTargets.forEach((control) => (locked && !this.exempt(control) ? this.lock(control) : this.unlock(control)))
    this.hintTargets.forEach((hint) => {
      if (!hint.textContent.trim()) hint.textContent = HINT
      hint.hidden = !locked || this.besideHolder(hint)
    })
  }

  lock(control) {
    if (control.hasAttribute(MARK)) return
    if (control.form?.matches("[data-controller~='admin--save-bar']") && control.name) {
      // Said once per element, so whoever marked it up notices: the lock has
      // silently done nothing for it. (In every environment -- the page has
      // no way to tell which it is in -- and to the console only.)
      if (!warned.has(control)) {
        warned.add(control)
        console.warn("admin--pending-lock: not locking a named control of the explicit-save form (it would count as a change); give the action its own form or drop the name", control)
      }
      return
    }
    if (control instanceof HTMLAnchorElement) {
      if (control.getAttribute("aria-disabled") === "true") return
      control.setAttribute("aria-disabled", "true")
    } else {
      if (control.disabled) return
      control.disabled = true
    }
    control.setAttribute(MARK, "")
  }

  unlock(control) {
    if (!control.hasAttribute(MARK)) return
    control.removeAttribute(MARK)
    if (control instanceof HTMLAnchorElement) control.removeAttribute("aria-disabled")
    else control.disabled = false
  }
}
