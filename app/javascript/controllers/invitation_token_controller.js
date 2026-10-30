import { Controller } from "@hotwired/stimulus"

// The invited person's page (app/views/invitations/show.html.erb): the
// reset page's script (`reset-token`, whose comments say why each rule is
// so) with two differences, which is why it is a controller of its own and
// not that one bent to fit:
//
// - the page does not know whose link it is, so the one question to the
//   server (`checkUrl`, a POST with the token in its body) is answered with
//   the person's address and name (200, JSON), which are written into the
//   page as TEXT, never as markup;
// - a link that is no good is a state of THIS page, not a redirect: 409 is
//   "used" (the Sign in link), 410 "expired". A page opened with no token
//   at all is "expired" too (an invalid link and a missing one are one
//   answer, M5).
//
// Anything else -- a 429, an error, no network -- shows the form without
// the address line: the form's own request decides anyway, and a check that
// could not be made must not cost a good link.
//
// THE TOKEN IS KEPT NOWHERE BUT THE FIELD, AND NOT PAST THE PAGE: it is
// emptied before Turbo's snapshot (`turbo:before-cache`) and before the
// browser's back/forward cache (`pagehide`), exactly as on the reset page.
//
// Lives in controllers/, not controllers/admin/: this page loads only the
// `application` entry point, like sign-in and the reset page.
export default class extends Controller {
  static targets = ["token", "form", "line", "email", "name", "expired", "used"]
  static values = { checkUrl: String }

  connect() {
    const token = window.location.hash.slice(1)
    if (token) {
      this.tokenTarget.value = token
      history.replaceState(history.state, "", window.location.pathname + window.location.search)
    }
    this.show(this.tokenTarget.value ? "form" : "expired")

    this.forget = () => { this.tokenTarget.value = "" }
    this.putAway = () => {
      this.forget()
      this.show("expired")
    }
    document.addEventListener("turbo:before-cache", this.forget)
    window.addEventListener("pagehide", this.putAway)

    if (token) this.check(token)
    else this.focus()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.forget)
    window.removeEventListener("pagehide", this.putAway)
  }

  show(state) {
    this.formTarget.hidden = state !== "form"
    this.expiredTarget.hidden = state !== "expired"
    this.usedTarget.hidden = state !== "used"
  }

  focus() {
    if (!this.formTarget.hidden) this.formTarget.querySelector("[autofocus]")?.focus()
  }

  async check(token) {
    this.hold(true)
    const answer = await this.ask(token)
    // The page was left or put away while the answer was on its way.
    if (!this.element.isConnected || this.tokenTarget.value !== token) return

    if (answer.state === "open") {
      this.emailTarget.textContent = answer.emailAddress
      this.lineTarget.hidden = false
      if (!this.nameTarget.value) this.nameTarget.value = answer.name
    }
    if (answer.state === "open" || answer.state === "unknown") {
      this.hold(false)
      this.focus()
    } else {
      this.forget()
      this.hold(false)
      this.show(answer.state)
    }
  }

  async ask(token) {
    try {
      const response = await fetch(this.checkUrlValue, {
        method: "POST",
        credentials: "same-origin",
        cache: "no-store",
        headers: { "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "", Accept: "application/json" },
        body: new URLSearchParams({ token }),
      })
      if (response.status === 410) return { state: "expired" }
      if (response.status === 409) return { state: "used" }
      if (!response.ok) return { state: "unknown" }

      const body = await response.json()
      return { state: "open", emailAddress: String(body.email_address || ""), name: String(body.name || "") }
    } catch {
      return { state: "unknown" }
    }
  }

  hold(held) {
    if (held) this.formTarget.setAttribute("aria-busy", "true")
    else this.formTarget.removeAttribute("aria-busy")
    this.formTarget.querySelectorAll("input:not([type=hidden])").forEach((field) => { field.readOnly = held })
  }
}
