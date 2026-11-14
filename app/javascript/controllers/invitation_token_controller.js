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
// THE PROVIDER'S BUTTON ("Continue with ..."), when the site has one, is a
// form of its own (`Admin::Ui::WayInButtonComponent`) with no token field:
// `carryToken` writes the token into it as the button is pressed, from the
// page's one field, and takes it out again as soon as the request is built,
// so neither a snapshot nor the back/forward cache holds a second copy. The
// token is in the body of that POST and in no address. Under SSO_REQUIRED
// there is no password form: the page's `form` target is a plain wrapper
// that holds the hidden field and the button, and no name field or address
// line exists to fill.
//
// Anything else -- a 429, an error, no network -- shows the form without
// the address line: the form's own request decides anyway.
//
// Lives in controllers/, not controllers/admin/: this page loads only the
// `application` entry point, like sign-in and the reset page.
export default class extends ResetTokenController {
  static targets = ["line", "email", "name", "expired", "used", "ways"]

  // Without an answer: the form while there is a token, "expired" without.
  show(state = this.tokenTarget.value ? "form" : "expired") {
    this.formTarget.hidden = state !== "form"
    this.expiredTarget.hidden = state !== "expired"
    this.usedTarget.hidden = state !== "used"
    this.waysTargets.forEach((ways) => { ways.hidden = state !== "form" })
  }

  // The `submit` of the provider's form, which the browser sends after this
  // handler: the field is there for the request and gone a tick later.
  carryToken(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement) || !this.tokenTarget.value) return

    const field = document.createElement("input")
    field.type = "hidden"
    field.name = "token"
    field.value = this.tokenTarget.value
    form.append(field)
    setTimeout(() => field.remove(), 0)
  }

  answered(answer) {
    if (answer.state === "open" && this.hasLineTarget) {
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
