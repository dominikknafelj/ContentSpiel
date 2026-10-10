import { Controller } from "@hotwired/stimulus"

// The AI assistant page's Copy buttons and the one-time token reveal
// (`admin/api_tokens/create`, design spec §6.1). Two jobs:
//
// - Copy: `navigator.clipboard` where it exists and is allowed (a secure
//   context -- https or localhost). Where it isn't (plain http on a LAN
//   address, a denied permission), the fallback is visible and needs no
//   dialog: the text itself is selected and the status line says to press
//   the copy shortcut. Never `alert()`.
// - Forget: on `pagehide` every `secret` target is blanked, so a page the
//   browser puts in its back/forward cache comes back without the raw
//   token (the response itself is `no-store` for every HTTP cache, and its
//   head opts out of Turbo's snapshot cache -- admin/api_tokens/create).
export default class extends Controller {
  static targets = ["secret", "status"]

  connect() {
    this.forget = () => this.secretTargets.forEach((element) => { element.textContent = "" })
    window.addEventListener("pagehide", this.forget)
  }

  disconnect() {
    window.removeEventListener("pagehide", this.forget)
  }

  async copy(event) {
    event?.preventDefault()
    const source = document.getElementById(event.params.source)
    if (!source) return

    try {
      if (!navigator.clipboard?.writeText) throw new Error("Clipboard API unavailable")
      await navigator.clipboard.writeText(source.textContent.trim())
      this.say("Copied", event.currentTarget)
    } catch (error) {
      this.select(source)
      this.say("Couldn't copy automatically — the text is selected, press Ctrl+C (⌘C on a Mac).", event.currentTarget)
    }
  }

  select(element) {
    const range = document.createRange()
    range.selectNodeContents(element)
    const selection = window.getSelection()
    selection.removeAllRanges()
    selection.addRange(range)
  }

  // The AI assistant page has a Copy button in each of its steps (the token,
  // the URL, the configuration) and a status line in each: the message goes
  // to the line in the section the pressed button sits in, else to the first.
  say(message, button) {
    if (!this.hasStatusTarget) return
    const section = button?.closest("section")
    const status = (section && this.statusTargets.find((target) => section.contains(target))) || this.statusTarget
    this.statusTargets.forEach((target) => { target.textContent = "" })
    status.textContent = message
  }
}
