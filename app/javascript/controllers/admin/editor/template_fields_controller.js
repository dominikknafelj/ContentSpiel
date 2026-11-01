import { Controller } from "@hotwired/stimulus"

// Shows the page settings' template-dependent fields (today the hero image and
// its alt text) for the template chosen in the select, and hides them
// otherwise. Each option carries the fields its template declares as
// `data-fields` (space separated); a group names the field it belongs to.
//
// The groups are always in the form and only `hidden` is toggled: a form that
// holds unsaved text is never replaced, so nothing here fetches or re-renders.
// It writes nothing but `hidden`, which is why a read-only (held) form can keep
// it: there the select is disabled and the groups show the stored template's.
export default class extends Controller {
  static targets = [ "select", "group" ]

  connect() {
    this.update()
  }

  update() {
    if (!this.hasSelectTarget) return

    const option = this.selectTarget.selectedOptions[0]
    const fields = (option?.dataset.fields || "").split(" ").filter(Boolean)
    this.groupTargets.forEach((group) => {
      group.hidden = !fields.includes(group.dataset.templateField)
    })
  }
}
