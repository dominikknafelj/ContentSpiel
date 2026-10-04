import { Controller } from "@hotwired/stimulus"

// Shows and hides one panel (`admin--disclosure-target="panel"`) on the same
// element's own say-so: a `data-action="admin--disclosure#toggle"` anywhere
// inside the controller's element flips it. Used by the editor header's
// interim schedule panel (Admin::EditorScreen::HeaderComponent), which the
// ⋯ menu's "Schedule…" and the "Edit schedule" button both open; the
// Schedule dialog replaces it. Opening focuses the panel's first field.
export default class extends Controller {
  static targets = [ "panel" ]

  toggle() {
    this.panelTarget.hidden ? this.show() : this.hide()
  }

  show() {
    this.panelTarget.hidden = false
    this.panelTarget.querySelector("input, select, textarea, button")?.focus()
  }

  hide() {
    this.panelTarget.hidden = true
  }
}
