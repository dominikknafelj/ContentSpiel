import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"

// The counter under a code field (code block spec §3, design answer C4):
// hidden until the text is within a tenth of the limit, then "18,412 of
// 20,000 characters", and over the limit, in the danger ink, "20,412 of
// 20,000 characters · 412 over". It counts what the server counts:
// `Array.from` walks code points, as Ruby's `String#length` does.
//
// It only READS the field's text. It sets no value, has nothing to tell
// autosave, and is one of the actions that survive in a form someone else
// holds (`Admin::EditorScreen::HeldFields::ALLOWED_ACTIONS`). The limit itself
// is the server's: a save over it is the form's ordinary 422, with the text
// left in the field.
//
// FOR A SCREEN READER the counter is the field's description only while it
// shows (`aria-describedby` is added and taken off with it: a hidden counter
// read out on every visit is noise), and it is ANNOUNCED TWICE AT MOST on the
// way up, never on every keystroke: once when it appears and once when the
// text passes the limit. The `announcer` target is a polite live region
// beside the counter that is written at those two moments only, with the
// counter's own words. A paste that goes from below the threshold to over
// the limit is one step up and one announcement, the over-limit one. A step
// down empties the region, so the same words can be said again the next
// time; nothing is said on the way down, and nothing when the script
// connects (the page that arrives is read by its own means, and the counter
// is then the field's description).
//
// What it writes into the page is recomputed from the field when it connects
// (the words, `hidden`, the colour, the description). The announcement is
// the one thing with nothing to recompute it from, so it is emptied when the
// script connects and when it disconnects.
const HIDDEN = 0
const SHOWN = 1
const OVER = 2

export default class extends Controller {
  static targets = [ "input", "output", "announcer" ]
  static values = { limit: Number, from: Number }

  connect() {
    this.announcer = this.hasAnnouncerTarget ? this.announcerTarget : null
    // A page shown again from a copy that kept an announcement says nothing
    // old, and the next step up changes the region and is said.
    if (this.announcer) this.announcer.textContent = ""
    this.state = this.paint()
  }

  disconnect() {
    if (this.announcer) this.announcer.textContent = ""
  }

  update() {
    const before = this.state
    this.state = this.paint()
    if (!this.announcer) return

    if (this.state > before) this.announcer.textContent = this.outputTarget.textContent
    else if (this.state < before) this.announcer.textContent = ""
  }

  // Draws the counter for the field as it is, and answers which of the three
  // states that is.
  paint() {
    const used = Array.from(this.inputTarget.value).length
    const over = used - this.limitValue
    const state = over > 0 ? OVER : (used >= this.fromValue ? SHOWN : HIDDEN)
    const numbers = { used: this.number(used), limit: this.number(this.limitValue) }
    const reader = messages(this.element)

    this.outputTarget.textContent = state === OVER
      ? reader.t("components.fields.code_field.over", { ...numbers, over: this.number(over) })
      : reader.t("components.fields.code_field.count", numbers)
    this.outputTarget.hidden = state === HIDDEN
    this.outputTarget.classList.toggle("text-danger-ink", state === OVER)
    this.outputTarget.classList.toggle("text-meta", state !== OVER)
    this.describe(state !== HIDDEN)
    return state
  }

  // The counter's id among the field's descriptions, or not: whatever else
  // describes the field stays.
  describe(shown) {
    const ids = (this.inputTarget.getAttribute("aria-describedby") || "").split(/\s+/).filter((id) => id && id !== this.outputTarget.id)
    if (shown) ids.push(this.outputTarget.id)
    if (ids.length) this.inputTarget.setAttribute("aria-describedby", ids.join(" "))
    else this.inputTarget.removeAttribute("aria-describedby")
  }

  // Grouped for the reader's language, as the server's first paint is; a
  // locale tag `Intl` rejects gets the bare digits.
  number(value) {
    try {
      return new Intl.NumberFormat(messages(this.element).locale()).format(value)
    } catch (error) {
      return String(value)
    }
  }
}
