import { Controller } from "@hotwired/stimulus"

// The dashboard's quick-create row (`Admin::DashboardScreen::QuickCreateComponent`).
// A post type just submits the form (a quick draft). Choosing "Page" opens the
// New page dialog instead, with the typed title carried over: the form holds
// a hidden real "New page" link wired to `admin--ui--dialog#open`, and this
// controller hands it the title as the `data-new-page-title-param` the dialog's
// form (`admin--new-record`) presets from, then clicks it -- so the dialog is
// opened by its one ordinary path and nothing here knows how a dialog works.
// Without JS (or without that link) the form submits and the server sends a
// "page" to the standalone New page screen.
export default class extends Controller {
  static targets = [ "title", "type", "pageTrigger" ]

  // A second submit while the first is in flight (Enter twice, a double
  // click) would create a second draft: ignore it until Turbo reports the
  // first one done (`turbo:submit-end`, wired in the template).
  submit(event) {
    if (this.submitting) return event.preventDefault()
    if (this.typeTarget.value !== "page" || !this.hasPageTriggerTarget) return

    event.preventDefault()
    this.pageTriggerTarget.dataset.newPageTitleParam = this.titleTarget.value
    this.pageTriggerTarget.click()
  }

  submitStart() { this.submitting = true }

  submitEnd() { this.submitting = false }
}
