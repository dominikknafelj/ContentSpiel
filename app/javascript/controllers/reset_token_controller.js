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
// IS THE LINK STILL GOOD? The page cannot know (it is drawn without the
// token), and the form's own request says so only after a password was
// typed twice. So, once, when the token came from the address, the script
// asks the server (`checkUrl`: a POST with the token in its body, never in
// an address). 410 is "not good": the page is replaced by the request
// page's "expired" state (`expiredUrl`, which names no token; replaced, so
// Back does not lead to a form that cannot work). Anything else -- 204, a
// 429, an error, no network -- shows the form: the form's request decides
// anyway, and a check that could not be made must not cost a good link.
// Until the answer is there the fields are read-only and the form says
// `aria-busy`, so nothing is typed into a form that is about to go. The
// form of a refused password (the 422) comes with its token from the
// server and is not asked about again.
//
// Before Turbo's snapshot only the field is emptied and the form is left on
// screen: the page is still shown for a moment while the next one is drawn,
// and `connect` decides what a restored snapshot shows. The browser's own
// cache restores a page without connecting anything again, so there the
// message is switched as well.
export default class extends Controller {
  static targets = ["token", "form", "incomplete"]
  static values = { checkUrl: String, expiredUrl: String }

  connect() {
    const token = window.location.hash.slice(1)
    if (token) {
      this.tokenTarget.value = token
      history.replaceState(history.state, "", window.location.pathname + window.location.search)
    }
    this.show()

    this.forget = () => { this.tokenTarget.value = "" }
    this.putAway = () => {
      this.forget()
      this.show()
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

  show() {
    const missing = !this.tokenTarget.value
    this.formTarget.hidden = missing
    this.incompleteTarget.hidden = !missing
  }

  // The browser gave no field the focus while the form was hidden, and a
  // field is not given it while it is read-only.
  focus() {
    if (!this.formTarget.hidden) this.formTarget.querySelector("[autofocus]")?.focus()
  }

  async check(token) {
    this.hold(true)
    const good = await this.ask(token)
    // The page was left or put away while the answer was on its way: it
    // has no token any more, and what is on screen is no longer this form.
    if (!this.element.isConnected || this.tokenTarget.value !== token) return

    if (good) {
      this.hold(false)
      this.focus()
    } else {
      this.forget()
      window.location.replace(this.expiredUrlValue)
    }
  }

  async ask(token) {
    try {
      const response = await fetch(this.checkUrlValue, {
        method: "POST",
        credentials: "same-origin",
        cache: "no-store",
        headers: { "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || "" },
        body: new URLSearchParams({ token }),
      })
      return response.status !== 410
    } catch {
      return true
    }
  }

  hold(held) {
    if (held) this.formTarget.setAttribute("aria-busy", "true")
    else this.formTarget.removeAttribute("aria-busy")
    this.formTarget.querySelectorAll("input:not([type=hidden])").forEach((field) => { field.readOnly = held })
  }
}
