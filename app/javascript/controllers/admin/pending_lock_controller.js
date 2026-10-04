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
// (`admin--pending-lock:connect`, which `admin--save-bar` answers). With no
// such form on the page nobody answers and nothing is locked.
//
// A button, input or select is `disabled`. A link can't be: it gets
// `aria-disabled="true"` and its click is swallowed here, in the capture
// phase and before Turbo or any `data-action` on the link sees it (Turbo
// ignores a click that is already cancelled). A control that was disabled
// for its own reasons is never touched, so unlocking doesn't enable it.
const HINT = "Save or cancel your changes first."
const MARK = "data-pending-locked"

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
    document.dispatchEvent(new CustomEvent("admin--pending-lock:connect"))
  }

  disconnect() {
    document.removeEventListener("admin--save-bar:state", this.onState)
    this.element.removeEventListener("click", this.swallow, true)
  }

  // A control streamed in while locked is locked too.
  controlTargetConnected(control) {
    if (this.locked) this.lock(control)
  }

  apply(locked) {
    this.locked = locked
    this.controlTargets.forEach((control) => (locked ? this.lock(control) : this.unlock(control)))
    this.hintTargets.forEach((hint) => {
      if (!hint.textContent.trim()) hint.textContent = HINT
      hint.hidden = !locked
    })
  }

  lock(control) {
    if (control.hasAttribute(MARK)) return
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
