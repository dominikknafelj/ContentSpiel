import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { enqueue } from "saving/queue"
import { get, post } from "editing/requests"
import { freeze, textOf } from "editing/freeze"

// THE TAB'S SIDE OF A RESERVATION (live-editing spec §4.2 to §4.4). One per
// editor, on the element `Admin::EditorScreen::LiveRegionComponent` renders,
// beside `admin--editing--live`; it hears the forms of the screen through
// events and owns no form.
//
// - CLAIMS a subject when a clean form gets its first change
//   (`admin--saving--autosave:dirty`), through the write queue, so the claim
//   is answered before that form's save is sent. A save renews the hold on
//   the server, so a subject this tab claimed less than half a hold ago is
//   not claimed again; one claimed longer ago is claimed again on the next
//   first change, and if somebody took it meanwhile that claim is refused.
// - RELEASES it when a block's form is closed (a section's panel, a collapsed
//   card) and when the editor is left, through the queue and so after the
//   form's last save. At `pagehide` nothing can wait for a queue: that one
//   release is a `fetch` with `keepalive`, the one write outside the queue
//   (a reload makes a new tab id; without it the block you were typing in
//   would read "editing this in another tab" until the old hold lapsed).
// - A REFUSED CLAIM OR SAVE (a 409 whose streams put the `lost` notice into
//   the card) turns that form read-only in place (`editing/freeze`) and
//   pauses its autosave: the text stays to be copied. "Discard" asks the live
//   script for the card as the server has it; "Remove" takes a deleted
//   block's card away.
// - A STRIP THAT SAYS SOMEONE ELSE HOLDS a subject says in how long the hold
//   lapses (`data-editing-expires-in`, from the server's `Editing::HOLD`). A
//   renewal sends no signal, and neither does a lapse, so at that time the
//   part is asked for again, through the live script's one line of reads: it
//   comes back editable, or held again with a new time. One timer per strip.
//
// IT HOLDS NO WORDING AND NO ADDRESS: every sentence is in the markup the
// server rendered and every URL (and the lists `editing/freeze` reads) is a
// value.
//
// WHERE STIMULUS IS A POOR FIT, honestly. (1) `held`, the claims this tab
// has made, is state that must outlive an element: a Turbo visit away
// disconnects this controller, and its releases are tasks in the write queue
// that run after it is gone (they use only values read before). (2) Four
// controllers cooperate by events and no one owns the picture: the autosave
// form says it is dirty, the section and the card say they were closed, the
// live script says a block was deleted, and this one answers by calling the
// autosave controller's `pause()` through the application (a controller
// reaching into another), because no target or outlet connects a form to a
// region that is its ancestor. (3) A strip is a TARGET of a controller whose
// element is far above it, and `stripTargetConnected` is used as "a server
// answer put a notice somewhere" -- a hook for a stream's effect that Turbo
// does not give; a stream rendered for a strip outside the region (none
// today) would be missed. (4) A timer per element is kept by hand (`timers`,
// keyed by the strip): Stimulus has no per-target state.
export default class extends Controller {
  static targets = [ "strip" ]
  static values = {
    claimUrl: String, releaseUrl: String, blockUrl: String, hold: Number, passOver: Number, notice: Number,
    rules: { type: Object, default: {} }
  }

  // Not in `connect`: Stimulus tells a controller of the targets that are
  // already in its element BEFORE it connects.
  initialize() {
    this.held = new Map()
    this.timers = new Map()
  }

  connect() {
    this.listeners = [
      [ "admin--saving--autosave:dirty", (event) => this.claim(event.detail.subject) ],
      [ "admin--editor--section:closed", (event) => this.release(`block-${event.detail.blockId}`) ],
      [ "admin--editor--blocks:toggled", (event) => { if (event.detail.hidden) this.release(`block-${event.detail.blockId}`) } ],
      [ "admin--editing--live:deleted", (event) => this.deleted(event.detail) ]
    ]
    this.listeners.forEach(([ name, act ]) => this.element.addEventListener(name, act))
    this.leaving = () => this.letGo()
    window.addEventListener("pagehide", this.leaving)
    // "Changed elsewhere" and a hold's notice share a post's `#editor-notice`.
    this.beforeStream = (event) => this.keepStaleBar(event)
    document.addEventListener("turbo:before-stream-render", this.beforeStream)
  }

  // A Turbo visit away: what this tab holds is released behind the saves the
  // visit waited for. The tasks are queued with the values read NOW, and run
  // when the queue gets to them, after this controller is gone.
  disconnect() {
    this.listeners.forEach(([ name, act ]) => this.element.removeEventListener(name, act))
    window.removeEventListener("pagehide", this.leaving)
    document.removeEventListener("turbo:before-stream-render", this.beforeStream)
    this.timers.forEach((timer) => clearTimeout(timer))
    this.timers.clear()
    const url = this.hasReleaseUrlValue ? this.releaseUrlValue : null
    if (url) [ ...this.held.keys() ].forEach((subject) => this.release(subject, url))
  }

  params(subject) { return subject === "record" ? {} : { block_id: subject.slice("block-".length) } }

  claim(subject) {
    if (!subject || !this.hasClaimUrlValue) return
    const last = this.held.get(subject)
    if (last && Date.now() - last < this.holdValue / 2) return

    this.held.set(subject, Date.now())
    const url = this.claimUrlValue
    const params = this.params(subject)
    enqueue(async () => {
      const answer = await post(url, params)
      if (answer.status === 204) return
      this.held.delete(subject)
      // Held by another tab: the answer's streams put the notice into the
      // card, and `stripTargetConnected` freezes the form when it appears --
      // but a save queued behind this claim must not find an editable form in
      // the meantime, so the form is stopped now.
      if (answer.status === 409) {
        this.lose(subject)
        Turbo.renderStreamMessage(answer.text)
      }
    })
  }

  release(subject, url = this.releaseUrlValue) {
    if (!this.held.delete(subject)) return
    const params = this.params(subject)
    enqueue(() => post(url, params))
  }

  letGo() {
    for (const subject of this.held.keys()) post(this.releaseUrlValue, this.params(subject), { keepalive: true })
    this.held.clear()
  }

  // A post's strip and its "Changed elsewhere" bar share `#editor-notice`.
  // While that bar shows it stays: its form is dead until a reload, whatever
  // else is true, and a reload shows the true state. A strip for a form that
  // is not stale shows as designed. (The other order -- a hold's strip first,
  // then a stale refusal -- cannot happen to one tab: a held post's form has
  // no autosave controller, so it sends nothing that could be stale.)
  keepStaleBar(event) {
    const stream = event.detail.newStream
    if (stream.getAttribute("target") !== "editor-notice") return
    if (!stream.querySelector("template")?.content.querySelector("[data-editing-kind]")) return
    if (document.getElementById("changed-elsewhere")) event.preventDefault()
  }

  stripTargetConnected(strip) {
    const subject = strip.dataset.editingSubject
    this.held.delete(subject)
    if (strip.dataset.editingKind !== "held") return this.lose(subject)

    const lapse = Number(strip.dataset.editingExpiresIn)
    if (Number.isFinite(lapse)) this.later(strip, () => this.dispatch("refresh", { detail: { subject } }), lapse + 250)
  }

  stripTargetDisconnected(strip) {
    clearTimeout(this.timers.get(strip))
    this.timers.delete(strip)
  }

  later(key, act, ms) {
    clearTimeout(this.timers.get(key))
    this.timers.set(key, setTimeout(() => { this.timers.delete(key); act() }, ms))
  }

  // Every unit of a subject: a block in a section is a tile's panel and
  // nothing else, a card is one unit.
  unitsOf(subject) { return [ ...this.element.querySelectorAll(`[data-editing-unit][data-editing-subject="${CSS.escape(subject)}"]`) ] }

  formsOf(subject) {
    return this.unitsOf(subject).flatMap((unit) => unit.matches("form") ? [ unit ] : [ ...unit.querySelectorAll("form[data-controller~='admin--saving--autosave']") ])
  }

  // This tab's text was not saved and will not be: the form stays as typed,
  // read-only, and sends nothing more.
  lose(subject) {
    for (const form of this.formsOf(subject)) {
      this.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave")?.pause()
      freeze(form, { rules: this.rulesValue, lock: (editor) => this.application.getControllerForElementAndIdentifier(editor, "admin--rich-text--editor")?.lock() })
    }
    // The translation header counts empty fields on screen, and a frozen
    // form's are not among them any more: it works its label out again.
    document.dispatchEvent(new CustomEvent("translate:changed"))
  }

  async copy(event) {
    const subject = event.currentTarget.dataset.editingSubject
    const status = event.currentTarget.closest("[data-editing-kind]").querySelector("[data-editing-copied]")
    const forms = this.formsOf(subject)
    const form = forms.find((each) => each.dataset.editingFrozen === "true") || forms[0]
    try {
      await navigator.clipboard.writeText(form ? textOf(form) : "")
      status.textContent = status.dataset.copied
    } catch {
      status.textContent = status.dataset.copyFailed
    }
    // Gone after 2 seconds (handoff 24).
    this.later(status, () => { status.textContent = "" }, 2000)
  }

  // The refused text is given up: the unit may be replaced although its form
  // is not clean, and it is replaced even if its version is the server's
  // (`admin--editing--live#refresh`). The notice goes at once: for a post it
  // stands outside the unit, and for the others the unit's replacement
  // would take it anyway.
  discard(event) {
    const subject = event.currentTarget.dataset.editingSubject
    event.currentTarget.closest("[data-editing-kind]")?.remove()
    this.dispatch("refresh", { detail: { subject, discard: true } })
  }

  // A deleted block's card, its tile and its panel go.
  remove(event) {
    const id = event.currentTarget.dataset.editingSubject.slice("block-".length)
    this.element.querySelectorAll(`#content_block_${CSS.escape(id)}, #block-${CSS.escape(id)}-panel`).forEach((each) => each.remove())
  }

  // Task 11 gives this its body. Until then the strip's and the menu's "Take
  // over" do nothing (Stimulus reports an action whose method is missing).
  takeOver() {}

  // A block was deleted while its form holds unsaved text (the list merge
  // kept its unit): the server words the notice, with who deleted it.
  async deleted({ blockId, unit }) {
    const answer = await get(this.blockUrlValue.replace(":block_id", blockId))
    const slot = unit.querySelector("[data-editing-strip-slot]") || document.getElementById(`block-${blockId}-hold`)
    if (answer.status !== 410 || !slot || !answer.text) return
    slot.replaceChildren(...new DOMParser().parseFromString(answer.text, "text/html").body.children)
  }
}
