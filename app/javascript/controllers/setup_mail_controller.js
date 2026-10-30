import { Controller } from "@hotwired/stimulus"

// The setup wizard's Mail step: choosing STARTTLS or TLS puts its port
// (587, 465: the radio's `data-port`) into Port, unless a port of another
// kind was typed there -- only an empty Port, or one holding the other
// choice's port, follows. The same rule as Settings → Mail's
// `admin--settings--mail`, which cannot be used here: the wizard loads the
// `application` entry only, never CS Studio's controllers.
const PORTS = ["587", "465"]

export default class extends Controller {
  static targets = ["port"]

  security(event) {
    if (!this.hasPortTarget) return
    const port = this.portTarget.value.trim()
    if (port !== "" && !PORTS.includes(port)) return
    this.portTarget.value = event.target.dataset.port
  }
}
