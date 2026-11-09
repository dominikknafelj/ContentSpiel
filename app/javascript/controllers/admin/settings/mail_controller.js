import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// The Mail card's login and focus, beside `admin--saving--pending-lock` and
// `mail-port` on the same root. Modelled on `admin--settings--ai`, whose
// comments say at length why each part is so. The port that follows the
// security is `mail-port`'s (`app/javascript/controllers/mail_port_controller.js`),
// shared with the wizard's Mail step.
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
// 3. Focus. A login write's answer replaces the login component, and a test
//    mail's answer the card's foot with the button in it: both would leave
//    the focus on <body>. It goes back to the new button (Replace / Send test
//    mail), or into the entry when the answer re-opened it with an error.
export default class extends Controller {
  static targets = ["chip", "entry", "input", "test"]

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
}
