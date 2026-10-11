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
//   A Turbo visit away releases at once (the visit was drained first), and so
//   it does what was still waiting: leaving pays everything in `owed()`. At
//   `pagehide` nothing can wait for a queue: the release of each subject is
//   a `fetch` with `keepalive`, and so is the withdrawal of a take-over
//   request this tab made (below): the two writes outside the queue. WHAT
//   REMAINS: a save
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
//   disables the button a tick later (in the same tick the card's menu, which
//   closes on a click that reached an enabled item, would stay open); a double
//   click is one request all the same, because `asking` is set at once.
//   `claimed`/`taken` -- nobody held it, or the holder was passed over -- and
//   the `taken` SIGNAL of a hand-over all end in `arrive`: the unit is asked
//   for (it comes back editable, from what the holder saved) and the focus
//   goes to its first field unless the person has moved on to another field
//   meanwhile; if that read did not draw it, the button is ready again and
//   says it did not work. `requested` shows the waiting status beside the
//   button and, after the pass-over time, asks once more of the SAME holder
//   (the server answers `taken`). A `released` signal while waiting means the
//   holder let go instead: the tab claims at once. A `claimed` signal (or a
//   strip of another person) means somebody else was first: it says so, asks
//   nobody and the person may press again. `pending` (another tab's request
//   stands) says so and leaves the button ready; a refusal or a failure says
//   it did not work and leaves the button ready. A request ENDS WITH ITS
//   ASKER: a Turbo visit, `pagehide` or the unit going away POSTS `withdraw`
//   (the holder is not told; its hand-over finds `nothing`).
//   HOLDER: a `requested` signal for a subject in `held` LOCKS THAT SUBJECT'S
//   FORMS LIGHTLY (`lockForms`: text controls `readOnly`, rich-text editors
//   not editable -- reversible, unlike `freeze` and `pause`, which are final)
//   at the moment it sends their flush, so nothing more can be typed into them,
//   and waits on THEIR OWN state, not the screen's (`drained` is about every
//   form; another block's typing or failing save must not hold this one):
//   no form outstanding, then clean and unchanged, then `hand_over`. On
//   `handed` the lock stays, the unit reads "Taken over by ..." and is fetched
//   (read-only, as the server draws it; asked again if that read fails).
//   If the save fails or is refused, the pass-over time runs out, the requester
//   is passed over first, or the hand-over answers `nothing`, the lock is
//   taken back exactly (what it locked, nothing else) and what follows is a
//   take-over that was not answered: the requester passes over, this tab
//   hears `taken` (or is refused at its next save) and the form is frozen with
//   the `lost` notice and its text. While it waits no claim renewal is sent for
//   the subject (`handing`). A tab passed over while awake reads "Taken over
//   by ..." too. The holder's tab is not told of its own hand-over by a signal
//   (it is the signal's `origin`): its own answer tells it. A tab that types
//   in ANOTHER block without a pause reads nothing until it pauses (the live
//   script's reads wait for the tab's writes to be quiet), so its unit shows
//   the notice only then.
// - A TAKE-OVER IS ANNOUNCED politely, once, in the unit's live region: the
//   strip carries the sentence (`data-editing-announce`); it is said when a
//   `taken` signal was heard, and in the tab that handed over or was passed
//   over. The requester hears nothing: it did it. A release followed by a
//   claim is no take-over and is not said. It is said a moment after the
//   strip appears, so that a card that was replaced has its region in the
//   document before it changes. THE STRIP THAT SAYS IT IS THE NEW HOLDER'S: a
//   read that was on its way when `taken` was heard (the one the `requested`
//   signal caused, a moment before) can have been drawn by the server while
//   the old holder still held the subject, and reaches the page after the
//   signal. Its strip names the person the subject was taken FROM, so it is
//   not the news: the tab remembers whose strip it showed when it heard the
//   signal (`announcing`) and says the sentence of the first strip that names
//   someone else. (The first build said it for the first strip to connect:
//   on a slow machine a third person heard the old holder's name, or -- that
//   strip replaced before its moment was up -- nothing at all.) So a third
//   person hears nothing when someone takes over from their OWN other tab:
//   the strip names the same person before and after.
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
    claimUrl: String, releaseUrl: String, takeOverUrl: String, handOverUrl: String, withdrawUrl: String, blockUrl: String, hold: Number, passOver: Number, notice: Number,
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
    // subject => { from: the element pressed, requested: whether the holder was asked,
    // holder: whose strip it was asked of, claiming: the holder let go and this tab claims,
    // third: somebody else claimed meanwhile }
    this.asking = new Map()
    // subject => token of the hand-over that waits for the subject's forms
    this.handing = new Map()
    // subject => when this tab handed it over (the strip says "Taken over by ...")
    this.lost = new Map()
    // subject => { holder, until }: its strip reads "Taken over by ..." until then
    this.taken = new Map()
    // subject => whose strip (a user id, or null for none) this tab showed when
    // it heard `taken`, for a take-over that has not been said yet
    this.announcing = new Map()
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
    const url = this.hasReleaseUrlValue ? this.releaseUrlValue : null
    const timeout = this.timeoutValue
    const owed = this.owed()
    if (url) owed.forEach((subject) => enqueue(() => post(url, this.params(subject), { timeout })))
    // What this tab asked for and will not be there to receive is withdrawn,
    // behind the writes the visit waited for (the values are read now).
    if (this.hasWithdrawUrlValue) {
      const withdraw = this.withdrawUrlValue
      for (const [ subject, asking ] of this.asking) if (asking.requested) enqueue(() => post(withdraw, this.params(subject), { timeout }))
    }
  }

  params(subject) { return subject === "record" ? {} : { block_id: subject.slice("block-".length) } }

  // WHAT THIS TAB OWES THE SERVER ON LEAVING: a release for every subject it
  // still holds there, each once. That is what is in `held` AND what is in
  // `releasing`: `release()` takes a subject out of `held` at once and parks
  // it while its form's last save is outstanding, and the first build walked
  // only `held` here, so a form closed with a save on the wire and then left
  // kept its hold for two minutes with nobody to release it (final review
  // I4). Both collections are emptied, so a release that was parked finds its
  // token gone and is not sent a second time.
  owed() {
    const subjects = new Set([ ...this.held.keys(), ...this.releasing.keys() ])
    this.held.clear()
    this.releasing.clear()
    return subjects
  }

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
  // (see the header). Until then the subject is in `releasing`, which leaving
  // the editor pays like `held` (`owed`).
  release(subject) {
    if (!this.held.delete(subject)) return
    const url = this.releaseUrlValue
    const timeout = this.timeoutValue
    const params = this.params(subject)
    const forms = this.formsOf(subject).map((form) => this.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave")).filter(Boolean)
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
    for (const subject of this.owed()) post(this.releaseUrlValue, this.params(subject), { keepalive: true })
    if (this.hasWithdrawUrlValue) for (const [ subject, asking ] of this.asking) if (asking.requested) post(this.withdrawUrlValue, this.params(subject), { keepalive: true })
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
      this.taken.delete(subject)
      return this.lose(subject)
    }

    const lapse = Number(strip.dataset.editingExpiresIn)
    if (Number.isFinite(lapse)) this.later(strip, () => this.dispatch("refresh", { detail: { subject } }), lapse + 250)
    const holder = strip.dataset.editingHolder
    // A strip drawn again while this tab is asking is still asking -- of the same
    // holder. Another person's strip (somebody claimed first) ends it: nothing is
    // asked of them, and the person may press again.
    const asking = this.asking.get(subject)
    if (asking) {
      if (asking.third || (asking.holder && asking.holder !== holder)) this.end(subject, "claimed")
      else this.showAsking(subject)
    }

    const handedAt = this.lost.get(subject)
    this.lost.delete(subject)
    // This tab handed it over, or was passed over while awake (ruling): "Taken
    // over by ..." for `notice`, then what the strip always reads (handoff 13).
    const handed = handedAt !== undefined && Date.now() - handedAt < LOST_FOR
    // A strip that still names whoever held it when the signal was heard is a
    // read from before the take-over (see the header): it says nothing and
    // leaves the announcement to the strip that names the new holder.
    const heard = this.announcing.has(subject) && this.announcing.get(subject) !== holder
    if (heard) this.announcing.delete(subject)
    if (handed) this.taken.set(subject, { holder, until: Date.now() + this.noticeValue })
    // The time is the SUBJECT's, not this strip's: a strip is part of a card
    // that is drawn again whenever anything about the block is heard (the new
    // holder's first saved words, a second read), and each strip of the same
    // holder that connects before the time is up reads "Taken over by ..."
    // for what is left of it. (The first build kept the time with the first
    // strip, and the sentence was gone with it, a second after the take-over.)
    const taken = this.taken.get(subject)
    if (taken && taken.holder === holder && taken.until > Date.now()) {
      const text = strip.querySelector("[data-editing-strip-text]")
      const usual = text.textContent
      text.textContent = strip.dataset.editingTakenText
      this.later(`notice:${subject}`, () => { this.taken.delete(subject); if (text.isConnected) text.textContent = usual }, taken.until - Date.now())
    } else {
      this.taken.delete(subject)
    }
    // Handoff 19: a take-over is announced politely, on that card -- never a
    // release followed by a claim, which is no take-over.
    if (handed || heard) this.announce(subject, strip.dataset.editingAnnounce)
  }

  stripTargetDisconnected(strip) {
    clearTimeout(this.timers.get(strip))
    this.timers.delete(strip)
    // A strip that goes with nothing in its place -- the unit was removed, or
    // came back editable -- ends this tab's asking, a tick later (Stimulus tells
    // of the two halves of a replacement separately). Unless the holder let go
    // and this tab claims: that answer ends it.
    const subject = strip.dataset.editingSubject
    setTimeout(() => {
      const asking = this.asking.get(subject)
      if (!asking || asking.claiming || this.stripTargets.some((each) => each.dataset.editingSubject === subject)) return
      this.withdraw(subject)
      this.end(subject)
    }, 0)
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

  // "Take over" on a strip or in a card's menu (handoff 2). One request per press: the
  // button is disabled at once, and a second press while this tab is asking is
  // nothing. See the header for the answers.
  takeOver(event) {
    const subject = event.currentTarget.dataset.editingSubject
    if (!subject || !this.hasTakeOverUrlValue || this.asking.has(subject)) return
    const strip = this.stripTargets.find((each) => each.dataset.editingSubject === subject && each.dataset.editingKind === "held")
    this.asking.set(subject, { from: event.currentTarget, requested: false, holder: strip?.dataset.editingHolder })
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
  // it lets go instead, the `released` signal does; if neither, this tab asks
  // again once the pass-over time has gone (of the same holder only) and is passed through.
  requested(subject) {
    const asking = this.asking.get(subject)
    asking.requested = true
    asking.claiming = false
    this.showAsking(subject)
    this.later(`ask:${subject}`, () => {
      const current = this.asking.get(subject)
      if (!current) return
      const strip = this.stripTargets.find((each) => each.dataset.editingSubject === subject && each.dataset.editingKind === "held")
      if (strip && (!current.holder || strip.dataset.editingHolder === current.holder)) this.ask(subject)
      else this.end(subject)
    }, this.passOverValue + 100)
  }

  // The subject is this tab's: it is asked for, comes back editable, and the
  // focus goes to its first field -- unless the person has put it somewhere
  // else meanwhile. If the read did not draw it, the button is ready again and
  // says it did not work.
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
    if (document.hidden) return
    if (this.heldByOther(subject)) return this.end(subject, "failed")
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

  // This tab no longer wants what it asked for: the request is cleared on the
  // server, so that the holder does not hand the subject to a tab that is not
  // waiting. (The holder is not told: its hand-over finds nothing.)
  withdraw(subject) {
    const asking = this.asking.get(subject)
    if (!asking?.requested || !this.hasWithdrawUrlValue) return
    const url = this.withdrawUrlValue
    const params = this.params(subject)
    const timeout = this.timeoutValue
    enqueue(() => post(url, params, { timeout }))
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

  // Whose `held` strip the subject shows now: a user id, or null without one.
  holderShown(subject) {
    return this.stripTargets.find((strip) => strip.dataset.editingSubject === subject && strip.dataset.editingKind === "held")?.dataset.editingHolder ?? null
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
    const asking = this.asking.get(subject)
    if (asking && reason === "released") {
      // The holder let go instead of handing over: nothing to wait for.
      asking.claiming = true
      clearTimeout(this.timers.get(`ask:${subject}`))
      return this.ask(subject)
    }
    if (asking && reason === "claimed") {
      // A third person was first: nothing is asked of them, and no timer asks again.
      asking.third = true
      clearTimeout(this.timers.get(`ask:${subject}`))
      this.later(`ask:${subject}`, () => this.end(subject), 10000)
      return
    }
    if (reason !== "taken") return
    if (asking) return this.arrive(subject)
    this.announcing.set(subject, this.holderShown(subject))
    this.later(`heard:${subject}`, () => this.announcing.delete(subject), 10000)
    // This tab held it and was passed over: it reads "Taken over by ..." (awake
    // with nothing unsaved is as much a hand-over as an answered one), and
    // unsaved text is refused now, at once, rather than at the next change.
    if (this.held.has(subject)) {
      this.lost.set(subject, Date.now())
      this.handing.delete(subject)
      if (this.unsaved(subject)) { this.held.delete(subject); this.claim(subject) }
    }
  }

  autosavesOf(subject) {
    return this.formsOf(subject).map((form) => this.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave")).filter(Boolean)
  }

  unsaved(subject) { return this.autosavesOf(subject).some((form) => !form.clean() || form.outstanding() || !form.unchanged()) }

  // A LIGHT, REVERSIBLE lock on a subject's forms: its text controls are
  // `readOnly` and its rich-text editors not editable, so nothing more can be
  // typed into them, and nothing else about the forms changes (no `data-action`
  // is taken away, no autosave is paused: `freeze` and `pause` are final, and a
  // paused form counts as failed). Disabled fields are left alone, because a
  // disabled control leaves the form's data and the form would look changed.
  // Returns what takes it back: only what this lock locked.
  lockForms(subject) {
    const undo = []
    const readonly = new Set(this.rulesValue.readonly_types || [])
    // A person typing keeps the cursor where it was when the lock is taken back
    // (a field that turned read-only loses the focus).
    const active = document.activeElement
    for (const form of this.formsOf(subject)) {
      for (const field of form.querySelectorAll("textarea, input")) {
        if (field.readOnly || field.disabled) continue
        if (field.tagName === "INPUT" && !readonly.has((field.getAttribute("type") || "text").trim().toLowerCase())) continue
        field.readOnly = true
        undo.push(() => { field.readOnly = false })
      }
      for (const element of form.querySelectorAll("[data-controller~='admin--rich-text--editor']")) {
        const editor = this.application.getControllerForElementAndIdentifier(element, "admin--rich-text--editor")
        if (!editor?.editable()) continue
        editor.lock()
        undo.push(() => editor.unlock())
      }
    }
    return () => {
      undo.forEach((act) => act())
      if (active && active !== document.body && active.isConnected && document.activeElement !== active) active.focus()
    }
  }

  // Someone asked for what this tab holds. This subject's forms -- and no
  // other -- are locked at once (nothing more can be typed into them), sent
  // now, and waited for on their own state; only when they hold nothing unsent
  // and the last save succeeded is the subject let go. The fields stay locked
  // after the hand-over (notice (a), and the unit is read as the server draws it
  // read-only). If the save fails or is refused, the pass-over time runs out,
  // the requester is passed over, or the hand-over finds nothing, the lock is
  // taken back exactly, and what follows is a take-over that was not answered:
  // this tab hears `taken` (or is refused at its next save) and the form is
  // frozen with the `lost` notice and its text.
  async handOver(subject) {
    if (!this.held.has(subject) || this.handing.has(subject) || !this.hasHandOverUrlValue) return
    const token = {}
    this.handing.set(subject, token)
    const url = this.handOverUrlValue
    const params = this.params(subject)
    const timeout = this.timeoutValue
    const deadline = Date.now() + this.passOverValue
    const unlock = this.lockForms(subject)
    const mine = () => this.handing.get(subject) === token && this.element.isConnected
    let handed = false
    try {
      const flushing = {}
      let sendable = false
      while (mine() && Date.now() < deadline) {
        const forms = this.autosavesOf(subject).filter((form) => form.element.isConnected)
        forms.forEach((form) => form.flush(flushing))
        if (forms.every((form) => !form.outstanding())) {
          if (!forms.every((form) => form.clean())) break
          if (forms.every((form) => form.unchanged())) { sendable = true; break }
          forms.forEach((form) => form.saveNow())
        }
        await new Promise((resolve) => setTimeout(resolve, 25))
      }
      if (!sendable || !mine()) return
      const answer = await enqueue(() => post(url, params, { timeout }))
      let state = null
      try { state = answer.status === 200 ? JSON.parse(answer.text).state : null } catch { /* not ours */ }
      handed = state === "handed"
    } finally {
      if (!handed) unlock()
      if (this.handing.get(subject) === token) this.handing.delete(subject)
    }
    if (!handed) return
    this.held.delete(subject)
    this.lost.set(subject, Date.now())
    this.showHandedOver(subject)
  }

  // The unit as the server draws it now (read-only, with the strip): asked for
  // again, a few times, if the read did not draw it -- the lock stays meanwhile.
  async showHandedOver(subject, tries = 0) {
    const waits = []
    this.dispatch("refresh", { detail: { subject, waits } })
    await Promise.all(waits)
    if (document.hidden || this.heldByOther(subject) || tries >= 3) return
    this.later(`handed:${subject}`, () => this.showHandedOver(subject, tries + 1), 2000 * (tries + 1))
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
