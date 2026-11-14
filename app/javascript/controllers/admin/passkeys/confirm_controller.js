import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// Confirm it's you (`Admin::Ui::ConfirmIdentityDialogComponent`), on the
// dialog's wrapper. `ensure()` opens the dialog and resolves true once a
// confirmation answers 200, false when the dialog closes otherwise (Cancel,
// ×, Escape). Its two callers:
// - another controller, through an outlet (`admin--passkeys--register`),
//   when the server answered a call 403 `{ "confirm": true }`, before it
//   makes the call again;
// - a refused Turbo Stream request (`Admin::RecentConfirmation`), whose
//   answer appends a `request` target here.
//
// THE FORM SENT AGAIN IS THE ONE THE GATE REFUSED, and only once. A form
// marked `data-confirm-identity` is remembered at its `turbo:submit-end`
// only when its answer was the gate's refusal (403 with CONFIRM_HEADER),
// so a form never refused is never sent again, and of two in flight the
// refused one is. The form is taken and forgotten in one step when the
// confirmation settles: sent again on true, dropped on false, so a
// cancelled change never comes back with a later request.
//
// THE OPTIONS ARE FETCHED WHEN THE DIALOG OPENS, never at the press: the
// browser's prompt opens only inside the press (`passkeys/ceremony`, "THE
// PROMPT OPENS IN THE PRESS"). "Use your passkey" stays disabled while no
// options are held, and each set is used once (the server takes its
// challenge with the first answer); a refusal or a closed prompt fetches a
// fresh set. While the dialog stands open the set is kept from lapsing
// (`passkeys/held_options`), a press on a set too old to use waits for a
// fresh one, and an answer that comes after the dialog closed or opened
// again is dropped: the server keeps one challenge, the latest. A closed
// prompt says nothing. Where the browser can use no passkey, the
// button and its "or" are hidden and the password is the way.
//
// The error line is the server's sentence, written as it comes; a passkey
// that failed in the browser, a network failure or an answer that is not
// the confirmation's JSON say `passkey_failed` (the passkey) or `limited`
// (the password), read from the wrapper's `data-messages`. The password is
// sent as JSON, and the field is emptied as it is sent, when the dialog
// closes and before Turbo caches the page. The passkey modules are imported
// on connect (`preload: false`), so a page without this dialog never
// fetches them.
const CONFIRM_HEADER = "X-Confirm-Identity"

export default class extends Controller {
  static targets = ["passkey", "divider", "error", "request"]
  static values = { optionsUrl: String, passwordUrl: String, passkeyUrl: String }

  async connect() {
    this.remembered = null
    this.pending = null
    this.remember = (event) => {
      const form = event.detail?.formSubmission?.formElement
      const response = event.detail?.fetchResponse
      if (!(form instanceof HTMLFormElement) || !form.matches("[data-confirm-identity]")) return
      if (response?.statusCode === 403 && response.header(CONFIRM_HEADER)) this.remembered = form
    }
    this.forget = () => this.close()
    document.addEventListener("turbo:submit-end", this.remember)
    document.addEventListener("turbo:before-cache", this.forget)
    this.closed = () => {
      this.password.value = ""
      this.held?.drop()
      this.settle(false)
    }
    this.dialog.addEventListener("close", this.closed)

    if (this.hasPasskeyTarget) await this.loadModules()
  }

  async loadModules() {
    if (this.held) return

    const [ceremony, { HeldOptions }] = await Promise.all([import("passkeys/ceremony"), import("passkeys/held_options")])
    if (this.held || !this.element.isConnected) return
    this.ceremony = ceremony
    this.held = new HeldOptions(() => this.load(), { wanted: () => Boolean(this.pending) })
    this.held.start()
  }

  disconnect() {
    document.removeEventListener("turbo:submit-end", this.remember)
    document.removeEventListener("turbo:before-cache", this.forget)
    this.dialog.removeEventListener("close", this.closed)
    this.held?.stop()
    this.held = null
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

  // A refused stream request's mark, taken out at once so a cached page
  // holds none. The refused form is read when the confirmation settles: its
  // `turbo:submit-end` has come by then.
  requestTargetConnected(element) {
    element.remove()
    this.ensure().then((confirmed) => {
      const form = this.remembered
      this.remembered = null
      if (confirmed && form?.isConnected) form.requestSubmit()
    })
  }

  async prepare() {
    if (!this.hasPasskeyTarget) return

    await this.loadModules()
    if (!this.held) return
    if (!this.ceremony.supported()) {
      this.passkeyTarget.hidden = true
      if (this.hasDividerTarget) this.dividerTarget.hidden = true
      return
    }

    this.held.drop()
    this.passkeyTarget.disabled = true
    const options = await this.held.refresh()
    if (options && this.pending) this.passkeyTarget.disabled = false
  }

  async load() {
    const answer = await this.ceremony.fetchOptions(this.optionsUrlValue)
    return answer.status === 200 ? answer.options : null
  }

  usePasskey(event) {
    event.preventDefault()
    if (!this.held) return
    const options = this.held.take()
    if (options) return this.prompt(options)
    if (!this.held.late) return

    this.passkeyTarget.disabled = true
    this.held.takeLate().then((fresh) => {
      if (fresh && this.pending) this.prompt(fresh)
      else if (this.pending) this.prepare()
    })
  }

  prompt(options) {
    this.passkeyTarget.disabled = true
    this.errorTarget.textContent = ""
    this.ceremony
      .get(options)
      .then((credential) => this.send(this.passkeyUrlValue, { credential: this.ceremony.toJSON(credential) }, "passkey"))
      .catch((error) => {
        if (!this.ceremony.cancelled(error)) this.fail("passkey")
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
    this.send(this.passwordUrlValue, { password }, "password")
  }

  // `way`: "passkey" or "password", whose sentence an answer that is not
  // the confirmation's gets.
  async send(url, body, way) {
    let response, answer
    try {
      response = await fetch(url, {
        method: "POST",
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content ?? "",
        },
        body: JSON.stringify(body),
      })
      answer = response.headers.get("Content-Type")?.includes("application/json") ? await response.json() : {}
    } catch {
      return this.fail(way)
    }

    if (response.ok && answer.confirmed) {
      this.settle(true)
      this.close()
    } else if (typeof answer.error === "string") {
      this.errorTarget.textContent = answer.error
    } else {
      this.fail(way)
    }
  }

  fail(way) {
    const words = messages(this.element)
    this.errorTarget.textContent = way === "passkey"
      ? words.t("components.ui.confirm_identity_dialog.passkey_failed")
      : words.t("components.ui.confirm_identity_dialog.limited")
  }

  close() {
    this.password.value = ""
    this.held?.drop()
    if (this.dialog.open) this.dialog.close()
  }

  settle(confirmed) {
    const pending = this.pending
    if (!pending) return

    this.pending = null
    if (!confirmed) this.remembered = null
    pending.resolve(confirmed)
  }
}
