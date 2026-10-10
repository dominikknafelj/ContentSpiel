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
//      - the main form has unsaved changes (any `admin--saving--save-bar` on the page,
//        heard as `admin--saving--save-bar:state`, decision D10) -> disabled,
//        "Save or cancel your changes first."
//    Both can apply at once (a changed field is itself a pending change);
//    then only the more specific hint shows. The button is deliberately not an
//    `admin--saving--pending-lock` control: that controller would re-enable it on its
//    own schedule and undo the first rule.
//
// 3. A key typed and not saved holds the main Save back (ledger C-M8). The
//    entry is a field of the key's own form; the main Save re-renders the
//    screen and dropped it without a word. While the entry is open and not
//    empty it carries `data-save-bar-holds` with the sentence the footer
//    shows, and the footer's Save is disabled (`admin--saving--save-bar`, "ONE FORM
//    AFTER ANOTHER"). Chosen over counting it in the leave guard: the key is
//    not a change of the Settings form, and its own Save or Cancel are right
//    there. And they stay usable (`admin--saving--pending-lock`, "ONE EXEMPTION"), or
//    a changed form and a typed key would lock each other: the INPUT for as
//    long as the entry is open (`data-pending-lock-exempt`; emptied to type
//    another key it must not be disabled under the caret), Save key while
//    the entry holds text. Cancel is never a locked control. Remove, Replace
//    and Test connection stay locked.
//
// 4. Focus. Cancel closes the entry under the focus, and a key write's answer
//    replaces the whole key component: both would leave focus on <body>. It
//    goes to the chip's button (Replace / Add key), or stays in the input
//    when the answer re-opened the entry with an error.
//
// Like `admin--saving--pending-lock`, it asks the save bar for its state once on
// connect (each controller arrives by its own dynamic import, and a form
// re-rendered after a refusal is unsaved from the start).
const SPECIFIC_HINT = "Save provider and model first. Tests the saved settings."
const PENDING_HINT = "Save or cancel your changes first."
const KEY_HINT = "Save or cancel the API key first."

export default class extends Controller {
  static targets = ["provider", "model", "test", "testHint", "chip", "entry", "input"]

  connect() {
    this.pending = false
    this.onState = (event) => {
      this.pending = Boolean(event.detail?.unsaved)
      this.refresh()
    }
    document.addEventListener("admin--saving--save-bar:state", this.onState)
    // The test's own submission. `admin--ui--busy` (on the test form) disables the
    // button for the flight and, when the answer lands, puts it back ENABLED
    // from a snapshot -- which would undo this gate (a Model edited during the
    // flight, a refresh() that re-enabled it for a second concurrent provider
    // call). So the flight is tracked here, counts as a reason to be disabled,
    // and the gate is re-applied in a microtask after `submit-end`, once busy's
    // own handler has run.
    this.testing = false
    // A key write that lands during the flight replaces the test form
    // (`#settings-ai-key-forms`); Turbo then dispatches the end on the
    // document element instead of the detached form, so the form is
    // remembered and that case accepted -- or the button stayed disabled
    // until a reload.
    this.onSubmitStart = (event) => {
      if (event.target.id !== "settings-ai-test-form") return
      this.testing = true
      this.testForm = event.target
      this.refresh()
    }
    this.onSubmitEnd = (event) => {
      const mine = event.target === this.testForm || (event.target === document.documentElement && this.testForm && !this.testForm.isConnected)
      if (!this.testing || !mine) return
      this.testing = false
      this.testForm = null
      queueMicrotask(() => this.refresh())
    }
    document.addEventListener("turbo:submit-start", this.onSubmitStart)
    document.addEventListener("turbo:submit-end", this.onSubmitEnd)
    this.started = true
    this.refresh()
    this.holdKey()
  }

  disconnect() {
    document.removeEventListener("admin--saving--save-bar:state", this.onState)
    document.removeEventListener("turbo:submit-start", this.onSubmitStart)
    document.removeEventListener("turbo:submit-end", this.onSubmitEnd)
    this.started = false
  }

  // The key component as a write's answer streamed it in (targets of the
  // first render connect before `connect()` and are left alone).
  entryTargetConnected(entry) {
    if (!this.started) return
    this.holdKey()
    const lost = !document.activeElement || document.activeElement === document.body
    if (!lost) return
    if (entry.hidden) this.chipTarget.querySelector("button")?.focus()
    else this.inputTarget.focus()
  }

  // See 3. Also asks the footer (and every `admin--saving--pending-lock`) to look
  // again.
  holdKey() {
    if (this.hasEntryTarget && this.hasInputTarget) {
      const open = !this.entryTarget.hidden
      const holds = open && this.inputTarget.value.trim() !== ""
      if (holds) this.entryTarget.setAttribute("data-save-bar-holds", KEY_HINT)
      else this.entryTarget.removeAttribute("data-save-bar-holds")
      // The INPUT is never locked out while the entry is open, text or no
      // text: emptying it to type another key (select all, delete) would
      // otherwise disable the very field the caret is in. Only Save key
      // depends on there being something to save.
      this.inputTarget.toggleAttribute("data-pending-lock-exempt", open)
    }
    document.dispatchEvent(new CustomEvent("admin--saving--save-bar:query"))
  }

  edit() {
    this.chipTarget.hidden = true
    this.entryTarget.hidden = false
    this.holdKey()
    this.inputTarget.focus()
  }

  cancel() {
    this.inputTarget.value = ""
    this.entryTarget.hidden = true
    this.chipTarget.hidden = false
    this.holdKey()
    this.chipTarget.querySelector("button")?.focus()
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
