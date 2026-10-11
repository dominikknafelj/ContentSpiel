import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { drained, enqueue } from "saving/queue"
import { get, post } from "editing/requests"
import { freeze, textOf } from "editing/freeze"

// THE TAB'S SIDE OF A RESERVATION (live-editing spec §4.2 to §4.4). One per
// editor, on the element `Admin::EditorScreen::LiveRegionComponent` renders,
// beside `admin--editing--live`; it hears the forms of the screen through
// events and owns no form.
//
// - CLAIMS a subject when a form changes (`admin--saving--autosave:dirty`),
//   through the write queue, so the claim is answered before that form's save
//   is sent. A save renews the hold on the server, but a person can type for
//   longer than a hold without a pause that saves: a subject this tab claimed
//   less than half a hold ago is not claimed again, one claimed longer ago is
//   claimed again on the next change (a renewal while typing, at most one per
//   half hold, and never two on the way at once). If somebody took the
//   subject meanwhile that claim is refused.
// - RELEASES it when a block's form is closed (a section's panel, a collapsed
//   card, a collapsed section's panels) and when the editor is left. The
//   release is sent through the queue, but only once none of the subject's
//   forms has anything left to send (`outstanding()`: a save on the wire, a
//   follow-up, a retry), or the follow-up save would claim the block back and
//   nothing would release it again; a new claim cancels a release that waits.
//   A Turbo visit away releases at once (the visit was drained first). At
//   `pagehide` nothing can wait for a queue: that one release is a `fetch`
//   with `keepalive`, the one write outside the queue. WHAT REMAINS: a save
//   still on the wire at the instant of a reload can reach the server after
//   that release (the save was sent first, the release is processed first)
//   and claim the block for the old tab id: the new page then reads "You're
//   editing this in another tab" until that hold lapses (`Editing::HOLD`).
//   Nothing in a page that is going away orders the two; the way out is Take
//   over (Task 11).
// - A REFUSED CLAIM OR SAVE (a 409 whose streams put the `lost` notice into
//   the card) turns that form read-only in place (`editing/freeze`) and
//   pauses its autosave: the text stays to be copied. A claim that fails for
//   the network, a timeout or a 5xx is not a refusal: the save behind it
//   claims on the server, so the subject stays in `held` (with time 0, "claim
//   again on the next change") and is released like any other. "Discard" asks
//   the live script for the card as the server has it, and keeps the notice
//   until that read has succeeded; "Remove" takes a deleted block's card away.
//   A notice must be seen: a panel that is hidden or a card that is collapsed
//   is opened where its form is frozen or its notice drawn.
// - A `claimed` SIGNAL for a unit in which this tab has unsaved text shows
//   nothing at once (the merge keeps the unit as it is): the person learns at
//   their next change or save, by the 409. With the renewal above that is the
//   narrow case of a tab that was offline or asleep.
// - A STRIP THAT SAYS SOMEONE ELSE HOLDS a subject says in how long the hold
//   lapses (`data-editing-expires-in`, from the server's `Editing::HOLD`). A
//   renewal sends no signal, and neither does a lapse, so at that time the
//   part is asked for again, through the live script's one line of reads: it
//   comes back editable, or held again with a new time. One timer per strip.
// - A DELETED BLOCK'S NOTICE (who deleted it) is asked of the live script, the
//   same line with the same retries, and drawn from its `notice` event; a 404
//   draws the plain sentence from the region's template.
//
// - TAKING OVER (live-editing spec §4.4; the server side is
//   `Editing::TakeOver`, whose class comment has every combination).
//   REQUESTER: "Take over" posts `take_over` through the write queue and
//   disables the button at once (a double click is one request: `asking`).
//   `claimed`/`taken` -- nobody held it, or the holder was passed over -- and
//   the `taken` SIGNAL of a hand-over all end in `arrive`: the unit is asked
//   for (it comes back editable, from what the holder saved) and the focus
//   goes to its first field unless the person has moved on to another field
//   meanwhile. `requested` shows the waiting status beside the button and,
//   after the pass-over time, asks once more (the server answers `taken`);
//   `pending` (another tab's request stands) says so and leaves the button
//   ready; a refusal or a failure says it did not work and leaves the button
//   ready. HOLDER: a `requested` signal for a subject in `held` makes this tab
//   send what it has -- `drained()` in a loop, until the subject's forms hold
//   nothing unsent, for at most the pass-over time -- and only then post
//   `hand_over`. Nothing unsaved is handed over: a form that cannot save
//   (paused by a 409, a failing save) or typing that never pauses long enough
//   sends no hand-over, the requester passes over, this tab hears that `taken`
//   signal (or its next save is refused) and the form is frozen as for any
//   refused claim. While it waits, no claim renewal is sent for the subject
//   (`handing`), and further typing is saved first. After `handed` this tab
//   fetches the unit; a unit that still holds a keystroke typed after the last
//   save is kept by the merge, so its text is sent once more -- and refused,
//   which freezes it with the `lost` notice and "Copy my text" instead of the
//   neutral "Taken over by ...". The holder's tab is not told by a signal (it
//   is the hand-over's `origin`): its own answer tells it.
// - A CHANGE OF HOLDER is said in the unit's polite live region, once: the
//   strip carries the sentence (`data-editing-announce`); it is said when the
//   strip's holder differs from the one this tab last saw, when a `taken`
//   signal was heard, and in the tab that handed over. The requester hears
//   nothing: it did it. It is said a moment after the strip appears, so that a
//   card that was replaced has its region in the document before it changes.
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
// keyed by the strip): Stimulus has no per-target state. (5) A release that
// waits for other controllers' state is a polling loop of its own (25 ms),
// because the autosave controller has no event for "nothing left to send".
const LOST_FOR = 30000
const ANNOUNCE_AFTER = 150

export default class extends Controller {
  static targets = [ "strip", "deleted" ]
  static values = {
    claimUrl: String, releaseUrl: String, takeOverUrl: String, handOverUrl: String, blockUrl: String, hold: Number, passOver: Number, notice: Number,
    timeout: { type: Number, default: 10000 },
    rules: { type: Object, default: {} }
  }

  // Not in `connect`: Stimulus tells a controller of the targets that are
  // already in its element BEFORE it connects.
  initialize() {
    this.held = new Map()
    this.claiming = new Set()
    this.releasing = new Map()
    this.timers = new Map()
    // subject => { from: the element pressed, requested: whether the holder was asked }
    this.asking = new Map()
    // subject => token of the hand-over that waits for the subject's forms
    this.handing = new Map()
    // subject => when this tab handed it over (the strip says "Taken over by ...")
    this.lost = new Map()
    // subject => the holder (user id) of the strip this tab last drew
    this.holders = new Map()
    // subjects whose `taken` signal was heard and not yet said
    this.announcing = new Set()
  }

  connect() {
    this.listeners = [
      [ "admin--saving--autosave:dirty", (event) => this.claim(event.detail.subject) ],
      [ "admin--editor--section:closed", (event) => this.release(`block-${event.detail.blockId}`) ],
      [ "admin--editor--blocks:toggled", (event) => { if (event.detail.hidden) this.collapsed(event.detail.blockId) } ],
      [ "admin--editing--live:deleted", (event) => this.deleted(event.detail) ],
      [ "admin--editing--live:notice", (event) => this.notice(event.detail) ],
      [ "admin--editing--live:holder", (event) => this.heardHolder(event.detail) ]
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
    this.releasing.clear()
    const url = this.hasReleaseUrlValue ? this.releaseUrlValue : null
    const timeout = this.timeoutValue
    if (url) [ ...this.held.keys() ].forEach((subject) => this.release(subject, url, { wait: false, timeout }))
  }

  params(subject) { return subject === "record" ? {} : { block_id: subject.slice("block-".length) } }

  claim(subject) {
    if (!subject || !this.hasClaimUrlValue) return
    // The subject is being handed over: what is typed now is saved first, and a
    // renewal would only tell the server this tab still wants it.
    if (this.handing.has(subject)) return
    // A release that was waiting for this subject's last save is not wanted
    // any more: the person is typing again.
    this.releasing.delete(subject)
    const last = this.held.get(subject)
    if (last && Date.now() - last < this.holdValue / 2) return
    if (this.claiming.has(subject)) return

    this.claiming.add(subject)
    this.held.set(subject, Date.now())
    const url = this.claimUrlValue
    const params = this.params(subject)
    const timeout = this.timeoutValue
    enqueue(async (isCurrent) => {
      try {
        const answer = await post(url, params, { timeout })
        // The page this was asked on is gone: its answer is nobody's.
        if (!isCurrent()) return
        if (answer.status === 204) return
        if (answer.status === 409) {
          this.held.delete(subject)
          // Held by another tab: the answer's streams put the notice into the
          // card, and `stripTargetConnected` freezes the form when it appears --
          // but a save queued behind this claim must not find an editable form
          // in the meantime, so the form is stopped now.
          this.lose(subject)
          Turbo.renderStreamMessage(answer.text)
        } else if (answer.status === 0 || answer.status >= 500) {
          // The network, a timeout or the server failed, not a refusal: the
          // save behind this claim claims on the server. Kept as held (time 0:
          // the next change claims again), so that closing or leaving releases.
          this.held.set(subject, 0)
        } else {
          this.held.delete(subject)
        }
      } finally {
        this.claiming.delete(subject)
      }
    })
  }

  // Lets go of a subject, once none of its forms has anything left to send
  // (see the header). `wait: false`: the editor is being left, the forms are
  // gone and the visit was drained.
  release(subject, url = this.releaseUrlValue, { wait = true, timeout = this.timeoutValue } = {}) {
    if (!this.held.delete(subject)) return
    const params = this.params(subject)
    const forms = wait ? this.formsOf(subject).map((form) => this.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave")).filter(Boolean) : []
    const token = {}
    this.releasing.set(subject, token)
    const go = () => {
      if (this.releasing.get(subject) !== token) return
      if (forms.some((form) => form.element.isConnected && form.outstanding())) { setTimeout(go, 25); return }
      this.releasing.delete(subject)
      enqueue(() => post(url, params, { timeout }))
    }
    go()
  }

  // A card collapsed: the block's form is closed, and so are those of the
  // blocks in it when it is a section.
  collapsed(blockId) {
    const subjects = new Set([ `block-${blockId}` ])
    this.element.querySelector(`#content_block_${CSS.escape(blockId)}`)?.querySelectorAll("[data-editing-unit][data-editing-subject]")
      .forEach((unit) => subjects.add(unit.dataset.editingSubject))
    subjects.forEach((subject) => this.release(subject))
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
    if (strip.dataset.editingKind !== "held") {
      this.asking.delete(subject)
      this.lost.delete(subject)
      return this.lose(subject)
    }

    const lapse = Number(strip.dataset.editingExpiresIn)
    if (Number.isFinite(lapse)) this.later(strip, () => this.dispatch("refresh", { detail: { subject } }), lapse + 250)
    // A strip drawn again while this tab is asking is still asking.
    if (this.asking.has(subject)) this.showAsking(subject)

    const holder = strip.dataset.editingHolder
    const before = this.holders.get(subject)
    this.holders.set(subject, holder)
    const handedAt = this.lost.get(subject)
    this.lost.delete(subject)
    const handed = handedAt !== undefined && Date.now() - handedAt < LOST_FOR
    const heard = this.announcing.delete(subject)
    // Handoff 13: in the tab the subject was taken from, the strip reads
    // "Taken over by ..." for `notice`, then what it always reads.
    if (handed) {
      const text = strip.querySelector("[data-editing-strip-text]")
      const usual = text.textContent
      text.textContent = strip.dataset.editingTakenText
      this.later(`notice:${subject}`, () => { if (text.isConnected) text.textContent = usual }, this.noticeValue)
    }
    // Handoff 19: a change of holder is announced politely, on that card.
    if (handed || heard || (before && before !== holder)) this.announce(subject, strip.dataset.editingAnnounce)
  }

  stripTargetDisconnected(strip) {
    clearTimeout(this.timers.get(strip))
    this.timers.delete(strip)
    // No holder is known once the strip is gone and none replaced it in the same
    // breath, so that the next holder is not taken for a change of this one.
    const subject = strip.dataset.editingSubject
    setTimeout(() => { if (!this.stripTargets.some((each) => each.dataset.editingSubject === subject)) this.holders.set(subject, null) }, 0)
  }

  // Said in the region beside the unit's strip slot, a moment after the strip
  // appears: a region that was inserted with its text is not always read.
  announce(subject, text) {
    this.later(`announce:${subject}`, () => {
      const strip = this.stripTargets.find((each) => each.dataset.editingSubject === subject)
      if (strip) this.announcerFor(strip)?.replaceChildren(text)
    }, ANNOUNCE_AFTER)
  }

  announcerFor(strip) {
    const slot = strip.closest("[data-editing-strip-slot]")
    return slot?.parentElement.querySelector(":scope > [data-editing-announcer]") || document.querySelector("#editor-notice ~ [data-editing-announcer]")
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
  // read-only, and sends nothing more -- and it is where the person can see
  // it (a notice nobody sees is text lost without their knowing).
  lose(subject) {
    for (const form of this.formsOf(subject)) {
      this.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave")?.pause()
      freeze(form, { rules: this.rulesValue, lock: (editor) => this.application.getControllerForElementAndIdentifier(editor, "admin--rich-text--editor")?.lock() })
    }
    this.reveal(subject)
    // The translation header counts empty fields on screen, and a frozen
    // form's are not among them any more: it works its label out again.
    document.dispatchEvent(new CustomEvent("translate:changed"))
  }

  // Shows what holds the subject's notice: a section's panel that is hidden is
  // opened through the section's own `open` (so its tile says so), and a card
  // that is collapsed is expanded.
  reveal(subject) {
    for (const unit of this.unitsOf(subject)) {
      if (unit.hidden && unit.matches("[data-admin--editor--section-target~='panel']")) {
        const host = unit.closest("[data-controller~='admin--editor--section']")
        if (host) this.application.getControllerForElementAndIdentifier(host, "admin--editor--section")?.open(unit.dataset.blockId)
      }
      const body = unit.querySelector("[data-block-body].hidden")
      if (body) {
        body.classList.remove("hidden")
        unit.querySelector(`[aria-controls="${CSS.escape(body.id)}"]`)?.setAttribute("aria-expanded", "true")
      }
    }
  }

  async copy(event) {
    const subject = event.currentTarget.dataset.editingSubject
    const status = event.currentTarget.closest("[data-editing-kind]").querySelector("[data-editing-copied]")
    const forms = this.formsOf(subject)
    const form = forms.find((each) => each.dataset.editingFrozen === "true") || forms[0]
    const text = form ? textOf(form) : ""
    try {
      // "Copied" is said only for text that was copied.
      if (!text) throw new Error("nothing to copy")
      await navigator.clipboard.writeText(text)
      status.textContent = status.dataset.copied
    } catch {
      status.textContent = status.dataset.copyFailed
    }
    // Gone after 2 seconds (handoff 24).
    this.later(status, () => { status.textContent = "" }, 2000)
  }

  // The refused text is given up: the unit may be replaced although its form
  // is not clean, and it is replaced even if its version is the server's
  // (`admin--editing--live#refresh`). The notice is taken away for the read
  // (for a post it stands outside the unit, and a part that shows an alert is
  // not replaced) and comes back, saying so, if the read did not succeed. The
  // status line of a record's header, which a refused save wrote and the
  // redrawn form does not own, is cleared once the form is drawn.
  async discard(event) {
    const subject = event.currentTarget.dataset.editingSubject
    const strip = event.currentTarget.closest("[data-editing-kind]")
    const slot = strip.parentElement
    const units = this.unitsOf(subject)
    const statusId = this.formsOf(subject)[0]?.getAttribute("data-admin--saving--autosave-status-id-value")
    strip.remove()
    const waits = []
    this.dispatch("refresh", { detail: { subject, discard: true, waits } })
    await Promise.all(waits)
    // Owed until the document is seen: the notice stays away, the read is coming.
    if (document.hidden) return
    if (units.some((unit) => unit.isConnected) && slot.isConnected) {
      const failed = strip.querySelector("[data-editing-copied]")
      if (failed) failed.textContent = failed.dataset.discardFailed
      slot.replaceChildren(strip)
      return
    }
    if (statusId) { const status = document.getElementById(statusId); if (status) status.textContent = "" }
  }

  // A deleted block's card, its tile and its panel go.
  remove(event) {
    const id = event.currentTarget.dataset.editingSubject.slice("block-".length)
    this.element.querySelectorAll(`#content_block_${CSS.escape(id)}, #block-${CSS.escape(id)}-panel`).forEach((each) => each.remove())
  }

  // "Take over" on a strip or in a card's menu (handoff 2). One request per
  // press: the button is disabled at once, and a second press while this tab is
  // asking is nothing. See the header for the answers.
  takeOver(event) {
    const subject = event.currentTarget.dataset.editingSubject
    if (!subject || !this.hasTakeOverUrlValue || this.asking.has(subject)) return
    this.asking.set(subject, { from: event.currentTarget, requested: false })
    // Not in this tick: the card's menu closes itself on a click that reached it
    // on an item that is not disabled, and an open menu keeps its unit from being drawn.
    setTimeout(() => this.showAsking(subject), 0)
    this.ask(subject)
  }

  ask(subject) {
    const url = this.takeOverUrlValue
    const params = this.params(subject)
    const timeout = this.timeoutValue
    return enqueue(async (isCurrent) => {
      const answer = await post(url, params, { timeout })
      if (!isCurrent() || !this.asking.has(subject)) return
      let state = null
      try { state = answer.status === 200 ? JSON.parse(answer.text).state : null } catch { /* not an answer of ours: a sign-in page */ }
      if (state === "taken" || state === "claimed") this.arrive(subject)
      else if (state === "requested") this.requested(subject)
      else if (state === "pending") this.end(subject, "pending")
      else this.end(subject, "failed")
    })
  }

  // The holder's tab was asked. If it answers, the `taken` signal ends this; if
  // not, this tab asks again once the pass-over time has gone and is passed through.
  requested(subject) {
    const asking = this.asking.get(subject)
    asking.requested = true
    this.showAsking(subject)
    this.later(`ask:${subject}`, () => {
      if (!this.asking.has(subject)) return
      if (this.heldByOther(subject)) this.ask(subject)
      else this.end(subject)
    }, this.passOverValue + 100)
  }

  // The subject is this tab's: it is asked for, comes back editable, and the
  // focus goes to its first field -- unless the person has put it somewhere
  // else meanwhile.
  async arrive(subject) {
    const asking = this.asking.get(subject)
    if (!asking) return
    this.asking.delete(subject)
    clearTimeout(this.timers.get(`ask:${subject}`))
    this.timers.delete(`ask:${subject}`)
    this.announcing.delete(subject)
    this.held.set(subject, Date.now())
    const waits = []
    this.dispatch("refresh", { detail: { subject, waits } })
    await Promise.all(waits)
    this.focusFirstField(subject, asking.from)
  }

  // Not arrived: the status says why (or nothing), and the button is ready.
  end(subject, status = null) {
    this.asking.delete(subject)
    clearTimeout(this.timers.get(`ask:${subject}`))
    this.timers.delete(`ask:${subject}`)
    this.takeOverButtons(subject).forEach((button) => { button.disabled = false })
    this.setTakeOverStatus(subject, status)
  }

  takeOverButtons(subject) {
    return [ ...this.element.querySelectorAll(`[data-action~='admin--editing--hold#takeOver'][data-editing-subject="${CSS.escape(subject)}"]`) ]
  }

  setTakeOverStatus(subject, key) {
    const strip = this.stripTargets.find((each) => each.dataset.editingSubject === subject)
    const status = strip?.querySelector("[data-editing-take-over-status]")
    if (status) status.textContent = key ? status.dataset[key] : ""
  }

  showAsking(subject) {
    if (!this.asking.has(subject)) return
    this.takeOverButtons(subject).forEach((button) => { button.disabled = true })
    this.setTakeOverStatus(subject, this.asking.get(subject)?.requested ? "waiting" : null)
  }

  heldByOther(subject) { return this.stripTargets.some((strip) => strip.dataset.editingSubject === subject && strip.dataset.editingKind === "held") }

  // The focus goes to the unit's first field when it is where the person was
  // left: nowhere, on the button that was pressed (or gone with it), or in the
  // unit itself. A person who went on to another field is left there.
  focusFirstField(subject, from, tries = 30) {
    const units = this.unitsOf(subject)
    const active = document.activeElement
    if (active && active !== document.body && active !== from && active.isConnected && !units.some((unit) => unit.contains(active))) return
    const visible = (field) => field.getClientRects().length > 0
    const field = units.flatMap((unit) => [ ...unit.querySelectorAll("form input:not([type=hidden]):not([disabled]), form textarea:not([disabled]), form select:not([disabled]), form [contenteditable=true]") ]).find(visible)
    if (field) return field.focus()
    // The editors of the new unit are mounted a moment after it is drawn.
    if (tries > 0 && !document.hidden) requestAnimationFrame(() => this.focusFirstField(subject, from, tries - 1))
  }

  // A holder signal, before the part is fetched (`admin--editing--live`).
  heardHolder({ subject, reason }) {
    if (reason === "requested") return this.handOver(subject)
    if (reason !== "taken") return
    if (this.asking.has(subject)) return this.arrive(subject)
    this.announcing.add(subject)
    this.later(`heard:${subject}`, () => this.announcing.delete(subject), 10000)
    // This tab held it and was passed over: unsaved text is refused now, at
    // once, rather than at the person's next change.
    if (this.held.has(subject)) {
      this.handing.delete(subject)
      if (this.unsaved(subject)) { this.held.delete(subject); this.claim(subject) }
    }
  }

  autosavesOf(subject) {
    return this.formsOf(subject).map((form) => this.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave")).filter(Boolean)
  }

  unsaved(subject) { return this.autosavesOf(subject).some((form) => !form.clean() || form.outstanding() || !form.unchanged()) }

  // Someone asked for what this tab holds: everything typed is sent first, and
  // the subject is let go only when nothing of it is left to send.
  async handOver(subject) {
    if (!this.held.has(subject) || this.handing.has(subject) || !this.hasHandOverUrlValue) return
    const token = {}
    this.handing.set(subject, token)
    const url = this.handOverUrlValue
    const params = this.params(subject)
    const timeout = this.timeoutValue
    const deadline = Date.now() + this.passOverValue
    let sendable = false
    try {
      while (this.element.isConnected && this.handing.get(subject) === token) {
        const result = await drained({ limit: Math.max(deadline - Date.now(), 100) })
        const forms = this.autosavesOf(subject).filter((form) => form.element.isConnected)
        if (result.timedOut || !forms.every((form) => form.clean())) break
        if (forms.every((form) => !form.outstanding() && form.unchanged())) { sendable = true; break }
        if (Date.now() >= deadline) break
      }
      if (!sendable || this.handing.get(subject) !== token) return
      const answer = await enqueue(() => post(url, params, { timeout }))
      let state = null
      try { state = answer.status === 200 ? JSON.parse(answer.text).state : null } catch { /* not ours */ }
      if (state !== "handed") return
      this.held.delete(subject)
      this.lost.set(subject, Date.now())
    } finally {
      if (this.handing.get(subject) === token) this.handing.delete(subject)
    }
    const waits = []
    this.dispatch("refresh", { detail: { subject, waits } })
    await Promise.all(waits)
    // A keystroke after the last save keeps the unit as it is (the merge does not
    // replace unsaved text): sent now, it is refused and frozen with the notice.
    if (this.autosavesOf(subject).some((form) => form.element.isConnected && !form.unchanged())) await drained()
  }

  // A block was deleted while its form holds unsaved text (the list merge
  // kept its unit): the server words the notice, with who deleted it, and the
  // live script fetches it through its own line (`notice`).
  deleted({ blockId }) {
    this.dispatch("refresh", { detail: { subject: `block-${blockId}`, notice: true } })
  }

  // The answer of that read: the notice (410), or, for a block no event
  // names, the plain sentence from the region's template (404).
  notice({ blockId, status, text }) {
    const slot = this.element.querySelector(`#block-${CSS.escape(blockId)}-hold`)
    if (!slot) return
    let html = null
    if (status === 410 && text) html = text
    else if (status === 404 && this.hasDeletedTarget) html = this.deletedTarget.innerHTML.replaceAll("block-0", `block-${blockId}`)
    if (html) slot.replaceChildren(...new DOMParser().parseFromString(html, "text/html").body.children)
  }
}
