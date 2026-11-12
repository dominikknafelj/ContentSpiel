import { Controller } from "@hotwired/stimulus"

// A passkey's button on the product layout's panel: "Sign in with a
// passkey" below the sign-in form, with its "or" divider, and "Use your
// passkey" on the second step, which has no divider (the target is
// optional). The server draws both hidden, and they are shown only where
// the browser can use a passkey, so a browser that cannot keeps the panel
// exactly as it was. The two pages differ only in the endpoints they name.
//
// Lives in controllers/ rather than controllers/admin/ because sign-in loads
// only the `application` entry point, which public pages load too. So the
// ceremony (`passkeys/ceremony`, `preload: false`) is imported when this
// controller connects, never by the module itself: a public page fetches
// this file and nothing behind it.
//
// THE OPTIONS ARE FETCHED BEFORE THE PRESS. The browser's prompt may open
// only inside the press (`passkeys/ceremony`, "THE PROMPT OPENS IN THE
// PRESS"), so the options are asked for at connect and held
// (`passkeys/held_options`, which replaces them before they lapse and when
// the tab is shown again), and the press hands them straight to `get`. The
// divider and the button are shown once the first options have arrived,
// and the button is disabled while none are held (its prompt open, or the
// first or the next set on its way), so no press is ever lost to a fetch. A
// press on a set too old to use waits for a fresh one. Each set is used
// once: the server takes its challenge with the first answer.
//
// The answer is posted as `credential` and the server says where to go
// (`{ location }`: CS Studio, or the page with its alert), whatever
// happened; the page is left for it. A prompt the person closed says
// nothing and fetches fresh options, for the next press. Nothing is written
// into the page but `hidden` and `disabled`, which connect decides afresh,
// so a page shown again from Turbo's snapshot is decided again too. The
// modules are imported at connect, so a public page fetches neither.
export default class extends Controller {
  static targets = ["divider", "button"]
  static values = { optionsUrl: String, verifyUrl: String }

  async connect() {
    this.buttonTarget.disabled = true
    const [ceremony, { HeldOptions }] = await Promise.all([import("passkeys/ceremony"), import("passkeys/held_options")])
    this.ceremony = ceremony
    if (!this.element.isConnected) return

    if (this.ceremony.supported()) {
      this.held = new HeldOptions(() => this.load())
      this.held.start()
      this.fetch()
    } else {
      if (this.hasDividerTarget) this.dividerTarget.hidden = true
      this.buttonTarget.hidden = true
    }
  }

  disconnect() {
    this.held?.stop()
    this.held = null
  }

  signIn(event) {
    event.preventDefault()
    if (!this.held) return
    const options = this.held.take()
    if (options) return this.prompt(options)
    if (!this.held.late) return

    this.buttonTarget.disabled = true
    this.held.takeLate().then((fresh) => {
      if (fresh) this.prompt(fresh)
      else this.fetch()
    })
  }

  prompt(options) {
    this.buttonTarget.disabled = true
    this.ceremony
      .get(options)
      .then((credential) => this.verify(credential))
      .catch((error) => {
        this.fetch()
        if (!this.ceremony.cancelled(error)) throw error
      })
  }

  async load() {
    const { status, options } = await this.ceremony.fetchOptions(this.optionsUrlValue)
    return status === 200 ? options : null
  }

  async fetch() {
    this.buttonTarget.disabled = true
    const options = await this.held?.refresh()
    if (!options || !this.element.isConnected) return

    if (this.hasDividerTarget) this.dividerTarget.hidden = false
    this.buttonTarget.hidden = false
    this.buttonTarget.disabled = false
  }

  async verify(credential) {
    const response = await fetch(this.verifyUrlValue, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content ?? "",
      },
      body: JSON.stringify({ credential: this.ceremony.toJSON(credential) }),
    })
    const { location } = await response.json()
    window.location.assign(location)
  }
}
