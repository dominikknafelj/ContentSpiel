import { Controller } from "@hotwired/stimulus"

// The password-reset token arrives after the "#" of the mailed link, which
// a browser never sends to a server: so it is in no request line, no span
// and no proxy log. This moves it into the form's hidden field and takes it
// out of the address bar; the form then carries it in its body, which the
// log filters. A page opened without it says the link is incomplete.
//
// Lives in controllers/ rather than controllers/admin/shell/ (where the
// plan had it, as `admin--shell--reset-token`) because the reset page loads
// only the `application` entry point, like sign-in and setup: an admin
// controller is never registered there (controllers/index.js).
//
// THE TOKEN IS KEPT NOWHERE BUT THE FIELD, AND NOT PAST THE PAGE. Writing a
// hidden input's `value` writes its attribute, so a copy of the document
// holds it: Turbo's snapshot, which it takes when the page is left by a
// link and shows again on Back, and the browser's own back/forward cache.
// The field is emptied before either is made (`turbo:before-cache`,
// `pagehide`). Neither comes before the form's own request has been built,
// so a submitted form still carries its token; and a page come back to has
// none and says the link is incomplete, which is true of it.
//
// Before Turbo's snapshot only the field is emptied and the form is left on
// screen: the page is still shown for a moment while the next one is drawn,
// and `connect` decides what a restored snapshot shows. The browser's own
// cache restores a page without connecting anything again, so there the
// message is switched as well.
export default class extends Controller {
  static targets = ["token", "form", "incomplete"]

  connect() {
    const token = window.location.hash.slice(1)
    if (token) {
      this.tokenTarget.value = token
      history.replaceState(history.state, "", window.location.pathname + window.location.search)
    }
    this.show()
    // The browser gave no field the focus while the form was hidden.
    if (!this.formTarget.hidden) this.formTarget.querySelector("[autofocus]")?.focus()

    this.forget = () => { this.tokenTarget.value = "" }
    this.putAway = () => {
      this.forget()
      this.show()
    }
    document.addEventListener("turbo:before-cache", this.forget)
    window.addEventListener("pagehide", this.putAway)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.forget)
    window.removeEventListener("pagehide", this.putAway)
  }

  show() {
    const missing = !this.tokenTarget.value
    this.formTarget.hidden = missing
    this.incompleteTarget.hidden = !missing
  }
}
