import { Controller } from "@hotwired/stimulus"

// The dashboard's "Start a draft" (the empty "Your drafts" card): a link to the
// quick-create row's title field. A fragment alone only scrolls to the field and
// focuses nothing, so this moves the focus there, ready to type. The link works
// without it (the fragment is its href), and without the field on the page the
// click is left to the browser. It holds no words.
export default class extends Controller {
  static values = { field: String }

  start(event) {
    const field = document.getElementById(this.fieldValue)
    if (!field) return

    event.preventDefault()
    field.focus()
  }
}
