import { Controller } from "@hotwired/stimulus"

// Confirm it's you (`Admin::Ui::ConfirmIdentityDialogComponent`), on the
// dialog's wrapper. `ensure()` opens the dialog and resolves true once a
// confirmation answers 200, false when the dialog closes otherwise (Cancel,
// ×, Escape). Its two callers:
// - another controller, through an outlet (`admin--passkeys--register`),
//   when the server answered a call 403 `{ "confirm": true }`, before it
//   makes the call again;
// - a refused Turbo Stream request (`Admin::RecentConfirmation`), whose
//   answer appends a `request` target here: the form that was sent, marked
//   `data-confirm-identity` and remembered at its `turbo:submit-start`, is
//   sent again once the person has confirmed.
//
// THE OPTIONS ARE FETCHED WHEN THE DIALOG OPENS, never at the press: the
// browser's prompt opens only inside the press (`passkeys/ceremony`, "THE
// PROMPT OPENS IN THE PRESS"). "Use your passkey" stays disabled while no
// options are held, and each set is used once (the server takes its
// challenge with the first answer); a refusal or a closed prompt fetches a
// fresh set. A closed prompt says nothing. Where the browser can use no
// passkey, the button and its "or" are hidden and the password is the way.
//
// The error line is the server's sentence, written as it comes. The
// password is sent as JSON, and the field is emptied as it is sent, when
// the dialog closes and before Turbo caches the page. The ceremony is
// imported on connect (`preload: false`), so a page without this dialog
// never fetches it.
export default class extends Controller {
  static targets = ["passkey", "divider", "error", "request"]
  static values = { optionsUrl: String, passwordUrl: String, passkeyUrl: String }

  async connect() {
    this.remembered = null
    this.pending = null
    this.options = null
    this.remember = (event) => {
      if (event.target instanceof HTMLFormElement && event.target.matches("[data-confirm-identity]")) this.remembered = event.target
    }
    this.forget = () => this.close()
    document.addEventListener("turbo:submit-start", this.remember)
    document.addEventListener("turbo:before-cache", this.forget)
    this.closed = () => {
      this.password.value = ""
      this.options = null
      this.settle(false)
    }
    this.dialog.addEventListener("close", this.closed)

    if (this.hasPasskeyTarget) this.ceremony = await import("passkeys/ceremony")
  }

  disconnect() {
    document.removeEventListener("turbo:submit-start", this.remember)
    document.removeEventListener("turbo:before-cache", this.forget)
    this.dialog.removeEventListener("close", this.closed)
    this.settle(false)
    this.remembered = null
  }

  get dialog() {
    return this.element.querySelector("dialog")
  }

  // The Password field's input (`PasswordFieldComponent`, whose `data` is
  // its own script's).
  get password() {
    return this.element.querySelector("input[name=password]")
  }

  ensure() {
    if (this.pending) return this.pending.promise

    let resolve
    const promise = new Promise((done) => (resolve = done))
    this.pending = { promise, resolve }
    this.errorTarget.textContent = ""
    this.password.value = ""
    this.dialog.showModal()
    this.password.focus()
    this.prepare()
    return promise
  }

  // A refused stream request's mark: the remembered form goes again once
  // confirmed. The mark is taken out at once, so a cached page holds none.
  requestTargetConnected(element) {
    element.remove()
    const form = this.remembered
    this.ensure().then((confirmed) => {
      if (confirmed && form?.isConnected) form.requestSubmit()
    })
  }

  async prepare() {
    if (!this.hasPasskeyTarget) return

    this.ceremony ||= await import("passkeys/ceremony")
    if (!this.ceremony.supported()) {
      this.passkeyTarget.hidden = true
      if (this.hasDividerTarget) this.dividerTarget.hidden = true
      return
    }

    this.options = null
    this.passkeyTarget.disabled = true
    const { status, options } = await this.ceremony.fetchOptions(this.optionsUrlValue)
    if (status !== 200 || !this.pending) return

    this.options = options
    this.passkeyTarget.disabled = false
  }

  usePasskey(event) {
    event.preventDefault()
    const options = this.options
    if (!options) return

    this.options = null
    this.passkeyTarget.disabled = true
    this.errorTarget.textContent = ""
    this.ceremony
      .get(options)
      .then((credential) => this.send(this.passkeyUrlValue, { credential: this.ceremony.toJSON(credential) }))
      .catch((error) => {
        if (!this.ceremony.cancelled(error)) throw error
      })
      .finally(() => {
        if (this.pending) this.prepare()
      })
  }

  confirmPassword(event) {
    event.preventDefault()
    const password = this.password.value
    this.password.value = ""
    this.errorTarget.textContent = ""
    this.send(this.passwordUrlValue, { password })
  }

  async send(url, body) {
    const response = await fetch(url, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content ?? "",
      },
      body: JSON.stringify(body),
    })
    const answer = response.headers.get("Content-Type")?.includes("application/json") ? await response.json() : {}
    if (response.ok && answer.confirmed) {
      this.settle(true)
      this.close()
    } else if (answer.error) {
      this.errorTarget.textContent = answer.error
    }
  }

  close() {
    this.password.value = ""
    this.options = null
    if (this.dialog.open) this.dialog.close()
  }

  settle(confirmed) {
    const pending = this.pending
    if (!pending) return

    this.pending = null
    pending.resolve(confirmed)
  }
}
