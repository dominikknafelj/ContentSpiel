import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// The Mail card's client side (spec "Settings → Mail", design answer M2),
// beside `admin--saving--pending-lock` on the same root. Modelled on
// `admin--settings--ai`, whose comments say at length why each part is so.
//
// 1. The login. Replace swaps the "Set on …" line for the entry (Username,
//    Password, Save login, Cancel); Cancel or Escape swaps it back and empties
//    the inputs. With no login stored the entry is open from the start. The
//    inputs belong to the login's own form, so nothing here is a change of
//    the Settings form.
//
// 2. A login typed and not saved holds the main Save back: while the entry is
//    open and an input holds text it carries `data-save-bar-holds` with the
//    sentence the footer shows (`components.settings_screen.mail_login.hold`),
//    and its inputs are exempt from the pending lock while it is open
//    (`admin--saving--pending-lock`, "ONE EXEMPTION").
//
// 3. Security. Choosing STARTTLS or TLS puts its port (587, 465: the radio's
//    `data-port`) into Port, unless a port of another kind was typed there:
//    only an empty Port, or one holding the other choice's port, follows.
//
// 4. Focus. A login write's answer replaces the login component, and a test
//    mail's answer the card's foot with the button in it: both would leave
//    the focus on <body>. It goes back to the new button (Replace / Send test
//    mail), or into the entry when the answer re-opened it with an error.
const PORTS = ["587", "465"]

export default class extends Controller {
  static targets = ["chip", "entry", "input", "port", "test"]

  connect() {
    this.started = true
    this.holdLogin()
  }

  disconnect() { this.started = false }

  entryTargetConnected(entry) {
    if (!this.started) return
    this.holdLogin()
    if (!this.focusLost) return
    if (entry.hidden) { if (this.hasChipTarget) this.chipTarget.querySelector("button")?.focus() }
    else this.inputTargets.find((input) => input.closest("[data-admin--settings--mail-target=entry]") === entry)?.focus()
  }

  testTargetConnected(button) {
    if (this.started && this.focusLost) button.focus()
  }

  get focusLost() { return !document.activeElement || document.activeElement === document.body }

  holdLogin() {
    if (this.hasEntryTarget) {
      const open = !this.entryTarget.hidden
      const holds = open && this.inputTargets.some((input) => input.value.trim() !== "")
      if (holds) this.entryTarget.setAttribute("data-save-bar-holds", messages(this.element).t("components.settings_screen.mail_login.hold"))
      else this.entryTarget.removeAttribute("data-save-bar-holds")
      this.inputTargets.forEach((input) => input.toggleAttribute("data-pending-lock-exempt", open))
    }
    document.dispatchEvent(new CustomEvent("admin--saving--save-bar:query"))
  }

  edit() {
    if (this.hasChipTarget) this.chipTarget.hidden = true
    this.entryTarget.hidden = false
    this.holdLogin()
    this.inputTargets[0]?.focus()
  }

  cancel() {
    // With no login stored there is no line to go back to: the entry stays.
    if (!this.hasChipTarget) return
    this.inputTargets.forEach((input) => {
      input.value = ""
      input.removeAttribute("aria-invalid")
      input.removeAttribute("aria-describedby")
    })
    this.entryTarget.hidden = true
    this.chipTarget.hidden = false
    this.holdLogin()
    this.chipTarget.querySelector("button")?.focus()
    this.element.querySelector("#settings-mail-login-errors")?.replaceChildren()
  }

  security(event) {
    if (!this.hasPortTarget) return
    const port = this.portTarget.value.trim()
    if (port !== "" && !PORTS.includes(port)) return
    this.portTarget.value = event.target.dataset.port
    // The footer counts a change by the form's own events.
    this.portTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
