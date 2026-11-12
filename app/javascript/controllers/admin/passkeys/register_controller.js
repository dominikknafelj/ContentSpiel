import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { messages } from "i18n/messages"

const CONFIRM_HEADER = "X-Confirm-Identity"

// Adding a passkey (Your account's Passkeys card, the enrolment page, the
// wizard's step), in the order WebKit allows (`passkeys/ceremony`, "THE
// PROMPT OPENS IN THE PRESS"):
//
// 1. `add` (the "Add a passkey…" press) fetches the registration options.
//    Refused by Confirm it's you's gate (403 `{ "confirm": true }`), it awaits
//    the outlet's `ensure()` and fetches them again only once confirmed: the
//    server keeps one challenge, so options are never asked for before the
//    confirmation that would spend the slot's. Then the Name dialog opens.
//    A cancelled confirmation does nothing more.
// 2. `continue` (the Name dialog's Continue) refuses a blank name
//    (`name_blank`) and otherwise calls the browser's prompt at once, in the
//    press, with the options held, then posts `credential` and `name` (and
//    `from`) with `methodValue`.
// 3. The answer: a redirect is followed (`Turbo.visit`), a Turbo Stream is
//    rendered (the card, the codes), and anything else says `failed`, or the
//    server's own sentence from a 422 `{ "error" }`. A closed prompt says
//    nothing, and its options are kept for the next press, since nothing was
//    sent; after an answer they are spent and fetched afresh.
// 4. A Continue with no options held, or a send the gate refused (403 with
//    CONFIRM_HEADER: the window lapsed while the Name dialog stood open),
//    goes back through `ensure()` when the server asks for it, fetches
//    fresh options (those held may have lapsed while the dialog stood
//    open) and prompts again with the same name. That prompt comes
//    after awaits, so WebKit may refuse it as outside a gesture; it is then
//    a closed prompt, which says nothing, and Continue works with the
//    options held.
//
// A page with no Name dialog (enrolment: the name is a field of the page,
// and "Add passkey" is the press that opens the prompt) holds options from
// connect, asked without the confirmation: a sign-in is one, so they come at
// once within its window, and otherwise the press goes the way of 4.
//
// Without an outlet (the wizard, which no confirmation gates) a 403 says
// `failed`. Where the browser can make no passkey, the add buttons are
// hidden, the `unsupported` sentences (the page's own words) are shown, and
// a Continue (Enter in the Name field) does nothing: no prompt is opened,
// so nothing is said to have failed. The words are the element's
// `data-messages`. Nothing here keeps
// a credential beyond its one send.
export default class extends Controller {
  static targets = ["name", "error", "dialog", "add", "unsupported"]
  static outlets = ["admin--passkeys--confirm"]
  static values = { optionsUrl: String, createUrl: String, from: String, method: { type: String, default: "post" } }

  async connect() {
    this.options = null
    this.ceremony = await import("passkeys/ceremony")
    this.unsupported = !this.ceremony.supported()
    if (this.unsupported) {
      this.addTargets.forEach((button) => { button.hidden = true })
      this.unsupportedTargets.forEach((sentence) => { sentence.hidden = false })
      return
    }
    if (!this.hasDialogTarget) this.refresh()
  }

  get dialog() {
    return this.dialogTarget.querySelector("dialog")
  }

  async add(event) {
    event?.preventDefault()
    this.ceremony ||= await import("passkeys/ceremony")
    const options = await this.fetchOptions()
    if (options === undefined) return

    this.options = options
    this.errorTarget.textContent = options ? "" : this.say("failed")
    if (this.hasNameTarget) this.nameTarget.value = ""
    if (!this.dialog.open) this.dialog.showModal()
    if (this.hasNameTarget) this.nameTarget.focus()
  }

  // The options, null when they could not be had, undefined when the person
  // cancelled the confirmation they waited on.
  async fetchOptions() {
    let answer = await this.request()
    if (answer?.status === 403 && answer.options?.confirm === true) {
      if (!this.hasAdminPasskeysConfirmOutlet) return null
      if (!(await this.adminPasskeysConfirmOutlet.ensure())) return undefined
      answer = await this.request()
    }
    return answer?.status === 200 && answer.options ? answer.options : null
  }

  async request() {
    try {
      return await this.ceremony.fetchOptions(this.optionsUrlValue)
    } catch {
      return null
    }
  }

  continue(event) {
    event.preventDefault()
    if (this.unsupported) return
    const name = this.hasNameTarget ? this.nameTarget.value.trim() : ""
    if (this.hasNameTarget && name === "") {
      this.errorTarget.textContent = this.say("name_blank")
      this.nameTarget.focus()
      return
    }
    const options = this.options
    if (!options) return this.confirmAgain(name)

    this.prompt(options, name)
  }

  prompt(options, name) {
    this.errorTarget.textContent = ""
    this.ceremony
      .create(options)
      .then((credential) => {
        this.options = null
        return this.send(this.ceremony.toJSON(credential), name)
      })
      .catch((error) => {
        if (this.ceremony.cancelled(error)) return
        this.options = null
        this.errorTarget.textContent = this.say("failed")
        this.refresh()
      })
  }

  async send(credential, name) {
    let response
    try {
      response = await fetch(this.createUrlValue, {
        method: this.methodValue.toUpperCase(),
        credentials: "same-origin",
        headers: {
          "Content-Type": "application/json",
          Accept: "text/vnd.turbo-stream.html, application/json",
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content ?? "",
        },
        body: JSON.stringify({ credential, name, from: this.fromValue }),
      })
    } catch {
      return this.refused()
    }

    if (response.status === 403 && response.headers.get(CONFIRM_HEADER)) return this.confirmAgain(name)

    const type = response.headers.get("Content-Type") || ""
    if (response.redirected) return Turbo.visit(response.url)
    if (response.ok && type.includes("turbo-stream")) return Turbo.renderStreamMessage(await response.text())

    const answer = type.includes("application/json") ? await response.json().catch(() => ({})) : {}
    this.refused(response.status === 422 && typeof answer.error === "string" ? answer.error : null)
  }

  async confirmAgain(name) {
    const options = await this.fetchOptions()
    if (options === undefined || !this.element.isConnected) return
    if (!options) return this.refused()

    this.options = options
    this.prompt(options, name)
  }

  refused(sentence = null) {
    if (!this.element.isConnected) return
    this.errorTarget.textContent = sentence || this.say("failed")
    this.refresh()
  }

  // Fresh options for the next Continue, while the dialog is open (always,
  // on a page with no dialog): the last set's challenge went with its
  // answer. A refusal by the gate leaves none, and the next Continue asks
  // for them through `ensure()`.
  async refresh() {
    const answer = await this.request()
    const waiting = !this.hasDialogTarget || this.dialog.open
    if (waiting && answer?.status === 200 && answer.options) this.options = answer.options
  }

  say(key) {
    return messages(this.element).t(`components.account_screen.passkey_dialog.${key}`)
  }
}
