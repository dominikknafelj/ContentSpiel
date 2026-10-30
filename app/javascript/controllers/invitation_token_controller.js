import ResetTokenController from "controllers/reset_token_controller"

// The invited person's page (app/views/invitations/show.html.erb). It IS
// the reset page's script (`reset-token`, whose comments say why each rule
// is so): the token moves from the address into the form's hidden field,
// the field is emptied before Turbo's snapshot and the back/forward cache,
// the fields are read-only while the one question is asked, and the
// question is the same POST with the token in its body. Only the hooks
// that class names are overridden here, because two things differ:
//
// - the page does not know whose link it is, so a good link is answered
//   with the person's address and name (200, JSON), which are written into
//   the page as TEXT, never as markup;
// - a link that is no good is a state of THIS page, not a redirect: 409 is
//   "used" (the Sign in link), 410 "expired". A page with no token at all
//   is "expired" too (an invalid link and a missing one are one answer,
//   M5), where the reset page says "incomplete".
//
// Anything else -- a 429, an error, no network -- shows the form without
// the address line: the form's own request decides anyway.
//
// Lives in controllers/, not controllers/admin/: this page loads only the
// `application` entry point, like sign-in and the reset page.
export default class extends ResetTokenController {
  static targets = ["line", "email", "name", "expired", "used"]

  // Without an answer: the form while there is a token, "expired" without.
  show(state = this.tokenTarget.value ? "form" : "expired") {
    this.formTarget.hidden = state !== "form"
    this.expiredTarget.hidden = state !== "expired"
    this.usedTarget.hidden = state !== "used"
  }

  answered(answer) {
    if (answer.state === "open") {
      this.emailTarget.textContent = answer.emailAddress
      this.lineTarget.hidden = false
      if (!this.nameTarget.value) this.nameTarget.value = answer.name
    }
    this.hold(false)
    if (answer.state === "open" || answer.state === "unknown") {
      this.focus()
    } else {
      this.forget()
      this.show(answer.state)
    }
  }

  async read(response) {
    if (response.status === 410) return { state: "expired" }
    if (response.status === 409) return { state: "used" }
    if (!response.ok) return { state: "unknown" }

    const body = await response.json()
    return { state: "open", emailAddress: String(body.email_address || ""), name: String(body.name || "") }
  }

  unknown() {
    return { state: "unknown" }
  }
}
