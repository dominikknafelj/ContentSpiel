import { Controller } from "@hotwired/stimulus"

// The answer to the password form on "Your account" (the notes handoff's
// decision 42), on the Password card when the page was drawn as that
// answer: saved (a redirect) or refused (the page again, 422).
//
// The result belongs to that card, so the page comes back AT it: the address
// ends in `#password`, the card is in view, and the focus is on the message
// -- the alert at the top of the card: the danger alert of a refusal, the
// success alert of a save (decision 43; no toast) -- so a screen reader
// announces it and has something to come back to.
//
// WHY A SCRIPT. The redirect's `Location` does name the fragment, and it
// never arrives: the form is a Turbo form, Turbo follows the 303 with
// `fetch` and visits `response.url`, which by the Fetch standard carries no
// fragment; and a 422 is drawn in place under the address the page had. In
// both cases Turbo then scrolls to the top. So the address is given its
// fragment here -- replaced through Turbo's own history, with the
// restoration identifier it has, as `admin--notes#syncAddress` does, never
// pushed -- and the card is scrolled to: smoothly, or at once for someone
// who asked for reduced motion.
//
// WHEN. A frame or two after the card connects: Turbo writes the address of
// its visit and scrolls to the top right after the render this connects in,
// and both must have happened first.
export default class extends Controller {
  connect() {
    this.frame = requestAnimationFrame(() => {
      this.frame = requestAnimationFrame(() => this.arrive())
    })
  }

  disconnect() {
    cancelAnimationFrame(this.frame)
  }

  arrive() {
    const url = new URL(window.location.href)
    if (url.hash !== `#${this.element.id}`) {
      url.hash = this.element.id
      const history = window.Turbo?.session?.history
      if (history?.restorationIdentifier) history.replace(url, history.restorationIdentifier)
      else window.history.replaceState(window.history.state, "", url.href)
    }

    const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    this.element.scrollIntoView({ block: "start", behavior: still ? "instant" : "smooth" })

    // The card's own alert (decision 43): the refusal's summary, or the
    // line that says the password was changed. Without scrolling again: the
    // card is what was brought into view, and the alert is at its top.
    const message = this.element.querySelector(".admin-error-summary, [data-password-saved]")
    if (!message) return
    if (!message.hasAttribute("tabindex")) message.setAttribute("tabindex", "-1")
    message.focus({ preventScroll: true })
  }
}
