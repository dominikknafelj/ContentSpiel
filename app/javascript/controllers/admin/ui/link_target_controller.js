import { Controller } from "@hotwired/stimulus"
import { createTargetSearch } from "rich_text/target_search"

// A `:link` field's "choose a page or post" (`Admin::Fields::LinkField`, whose
// comment has the form's contract). The named input is the field's value; a
// pick writes `cs:<type>/<id>` into it and fires its `change`, so the form's
// autosave sends it as it sends any field. The search is the rich text
// picker's own (`rich_text/target_search`), and with it the same list, the same
// combobox keys and the same read scope.
//
// Nothing here sends a request of its own but the search's GET: a save goes
// through the form, and so through the write queue.
//
// A held form has no actions and read-only inputs (`HeldFields`, `freeze.js`):
// the search can't be typed into, so nothing below can run, and no state of its
// own survives: what is shown is what the elements hold, which is also what
// Turbo's snapshot keeps.
export default class extends Controller {
  static targets = ["value", "chip", "title", "clear", "note", "searchBox", "search", "message", "listbox"]
  static values = { url: String, locale: String, untitled: String }

  connect() {
    this.targetSearch = createTargetSearch({
      input: this.searchTarget,
      listbox: this.listboxTarget,
      message: this.messageTarget,
      url: this.urlValue,
      locale: this.localeValue,
      onPick: (row) => this.pick(row)
    })
  }

  disconnect() {
    this.targetSearch?.destroy()
    this.targetSearch = null
  }

  // Only the search's own events stop here: the named input's are the form's.
  swallow(event) {
    if (event.target === this.searchTarget) event.stopPropagation()
  }

  // Enter with no row highlighted must not submit the form around the field.
  holdEnter(event) {
    event.preventDefault()
  }

  pick(row) {
    this.titleTarget.textContent = row.title || this.untitledValue
    // What the server would say on reload (`LinkField#not_public?`), from what
    // the row says: a draft, a scheduled one, or one with no address yet.
    this.noteTarget.hidden = row.status === "live" && Boolean(row.path)
    this.write(`cs:${row.type}/${row.id}`)
    this.show(true)
    this.searchTarget.value = ""
    this.searchTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.clearTarget.focus()
  }

  clear() {
    this.noteTarget.hidden = true
    this.write("")
    this.show(false)
    this.valueTarget.focus()
  }

  write(value) {
    this.valueTarget.value = value
    this.valueTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.valueTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  show(chosen) {
    this.valueTarget.hidden = chosen
    this.chipTarget.hidden = !chosen
    this.searchBoxTarget.hidden = chosen
  }
}
