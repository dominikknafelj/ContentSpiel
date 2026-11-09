import { Controller } from "@hotwired/stimulus"

// The Mail form's port rule, on Settings → Mail and in the setup wizard's
// Mail step (`Admin::SettingsScreen::MailFieldsComponent`): choosing STARTTLS
// or TLS puts its port (587, 465: the radio's `data-port`) into Port, unless
// a port of another kind was typed there -- only an empty Port, or one
// holding the other choice's port, follows.
//
// A top-level controller, because the wizard loads the `application` entry
// only, never CS Studio's controllers; CS Studio registers every top-level
// controller too.
const PORTS = ["587", "465"]

export default class extends Controller {
  static targets = ["port"]

  security(event) {
    if (!this.hasPortTarget) return
    const port = this.portTarget.value.trim()
    if (port !== "" && !PORTS.includes(port)) return
    this.portTarget.value = event.target.dataset.port
    // Settings' save bar counts a change by the form's own events.
    this.portTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
