import { Controller } from "@hotwired/stimulus"

// The one-time token reveal's forgetting (`admin/api_tokens/create`). On
// `pagehide` every `secret` target is blanked -- the token's copy box and the
// client configuration that holds it -- so a page the browser puts in its
// back/forward cache comes back without the raw token (the response itself
// is `no-store` for every HTTP cache, and its head opts out of Turbo's
// snapshot cache). Copying is `admin--ui--clipboard`'s, which reads a copy
// box's text and keeps no copy of it, so blanking the text forgets it whole.
export default class extends Controller {
  static targets = ["secret"]

  connect() {
    this.forget = () => this.secretTargets.forEach((element) => { element.textContent = "" })
    window.addEventListener("pagehide", this.forget)
  }

  disconnect() {
    window.removeEventListener("pagehide", this.forget)
  }
}
