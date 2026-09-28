import { Controller } from "@hotwired/stimulus"

// Autocomplete for the post editor's comma-separated tag input (cs-studio
// spec §5.2, `Admin::TagInputComponent`). A native `<input list=...>`'s own
// `<datalist>` always matches -- and, once a suggestion is picked, replaces
// -- the input's *whole* value, which is wrong the moment this field
// already holds more than one tag: picking "rails" while the field reads
// "ruby, ra" would otherwise wipe out "ruby, " too. Rebuilding the
// datalist's own `<option>` values on every keystroke, each one the *whole*
// prospective value (everything already typed up to the last comma, plus
// one candidate name) rather than the bare candidate name, is what makes
// picking a suggestion complete only the segment currently being typed
// instead of replacing the whole field -- the browser still does a literal
// whole-value swap when an option is chosen, but the option's own text is
// engineered so that swap lands on the right result.
export default class extends Controller {
  static targets = ["input", "datalist"]
  static values = { names: Array }

  connect() {
    this.update()
  }

  update() {
    const value = this.inputTarget.value
    const lastComma = value.lastIndexOf(",")
    const prefix = lastComma === -1 ? "" : `${value.slice(0, lastComma + 1)} `
    const typed = (lastComma === -1 ? value : value.slice(lastComma + 1)).trim().toLowerCase()
    const already = value
      .slice(0, lastComma === -1 ? 0 : lastComma + 1)
      .split(",")
      .map((name) => name.trim().toLowerCase())
      .filter(Boolean)

    this.datalistTarget.replaceChildren(
      ...this.namesValue
        .filter((name) => name.toLowerCase().startsWith(typed) && !already.includes(name.toLowerCase()))
        .map((name) => {
          const option = document.createElement("option")
          option.value = `${prefix}${name}`
          return option
        })
    )
  }
}
