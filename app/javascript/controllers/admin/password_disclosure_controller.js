import { Controller } from "@hotwired/stimulus"

// "Set a new password…" on the user editor (round 3 Task 12): a `<details>`
// holding the two password fields. Opening it without typing is no change (a
// blank password means "keep the current one": `Users::Save`). CLOSING it
// again clears what was typed -- a half-typed password must not ride along
// with the next Save of a form that looks as if it were not changing one --
// and says so to the form: a bubbling `input` on each field that held
// something, so the strength meter and the footer's count see it go.
export default class extends Controller {
  toggled() {
    if (this.element.open) return
    this.element.querySelectorAll("input").forEach((field) => {
      if (field.value === "") return
      field.value = ""
      field.dispatchEvent(new Event("input", { bubbles: true }))
    })
  }
}
