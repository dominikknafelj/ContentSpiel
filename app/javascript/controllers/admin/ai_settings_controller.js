import { Controller } from "@hotwired/stimulus"

// The AI translation card's client side (round 3, Task 7).
//
// 1. Replace / Add key swaps the key chip for the key's input, Cancel (or
//    Escape) swaps it back and empties the input. The input is never
//    pre-filled -- the key is never in the page -- and belongs to the key's own
//    form, so none of this is a change of the Settings form.
//
// 2. Test connection tests the SAVED settings, so it is gated here, in one
//    place, on two independent rules:
//      - Provider or Model differ from their `data-saved-value` -> disabled,
//        "Save provider and model first. Tests the saved settings."
//      - the main form has unsaved changes (any `admin--save-bar` on the page,
//        heard as `admin--save-bar:state`, decision D10) -> disabled,
//        "Save or cancel your changes first."
//    Both can apply at once (a changed field is itself a pending change);
//    then only the more specific hint shows. The button is deliberately not an
//    `admin--pending-lock` control: that controller would re-enable it on its
//    own schedule and undo the first rule.
//
// Like `admin--pending-lock`, it asks the save bar for its state once on
// connect (each controller arrives by its own dynamic import, and a form
// re-rendered after a refusal is unsaved from the start).
const SPECIFIC_HINT = "Save provider and model first. Tests the saved settings."
const PENDING_HINT = "Save or cancel your changes first."

export default class extends Controller {
  static targets = ["provider", "model", "test", "testHint", "chip", "entry", "input"]

  connect() {
    this.pending = false
    this.onState = (event) => {
      this.pending = Boolean(event.detail?.unsaved)
      this.refresh()
    }
    document.addEventListener("admin--save-bar:state", this.onState)
    // The test's own submission. `admin--busy` (on the test form) disables the
    // button for the flight and, when the answer lands, puts it back ENABLED
    // from a snapshot -- which would undo this gate (a Model edited during the
    // flight, a refresh() that re-enabled it for a second concurrent provider
    // call). So the flight is tracked here, counts as a reason to be disabled,
    // and the gate is re-applied in a microtask after `submit-end`, once busy's
    // own handler has run.
    this.testing = false
    this.onSubmitStart = (event) => {
      if (event.target.id !== "settings-ai-test-form") return
      this.testing = true
      this.refresh()
    }
    this.onSubmitEnd = (event) => {
      if (event.target.id !== "settings-ai-test-form") return
      this.testing = false
      queueMicrotask(() => this.refresh())
    }
    document.addEventListener("turbo:submit-start", this.onSubmitStart)
    document.addEventListener("turbo:submit-end", this.onSubmitEnd)
    this.refresh()
    document.dispatchEvent(new CustomEvent("admin--save-bar:query"))
  }

  disconnect() {
    document.removeEventListener("admin--save-bar:state", this.onState)
    document.removeEventListener("turbo:submit-start", this.onSubmitStart)
    document.removeEventListener("turbo:submit-end", this.onSubmitEnd)
  }

  edit() {
    this.chipTarget.hidden = true
    this.entryTarget.hidden = false
    this.inputTarget.focus()
  }

  cancel() {
    this.inputTarget.value = ""
    this.entryTarget.hidden = true
    this.chipTarget.hidden = false
    // A refusal ("Enter the API key first.") belongs to the entry just closed.
    const errors = this.element.querySelector("#settings-ai-key-errors")
    if (errors) errors.replaceChildren()
    this.inputTarget.removeAttribute("aria-invalid")
    this.inputTarget.removeAttribute("aria-describedby")
  }

  get changed() {
    return [this.providerTarget, this.modelTarget].some((field) => field.value.trim() !== (field.dataset.savedValue || "").trim())
  }

  refresh() {
    if (!this.hasTestTarget) return
    const changed = this.changed
    const hint = changed ? SPECIFIC_HINT : this.pending ? PENDING_HINT : ""
    this.testTarget.disabled = changed || this.pending || this.testing
    if (this.hasTestHintTarget) {
      this.testHintTarget.textContent = hint
      this.testHintTarget.hidden = hint === ""
    }
  }
}
