import { Controller } from "@hotwired/stimulus"
import { listen, TAB } from "live/connection"
import { settle } from "live/state"
import { quiet, writeCount } from "saving/queue"
import { get } from "editing/requests"
import { anchored, holds, mergeList, mergeUnits } from "editing/merge"

// LIVE REFRESH of an open page or post editor (live-editing spec §3.2). On
// the element `Admin::EditorScreen::LiveRegionComponent` renders.
//
// It hears, on the record's stream (`Editing::Channel`), THAT something
// changed -- a kind, a block's id, a reason -- and fetches that part with a
// plain GET through the read scope, as its viewer may see it now: one block,
// the block list (`structure`), or the record's own form. What comes back is
// handed to `editing/merge`, which never replaces a form that holds unsaved
// changes. The tab that made the change skips its own signal (`origin`).
// A `holder` signal (a claim, a release, a request, a take-over) leads to the
// same fetch of the same part, through the same line: the block's own card
// (or tile and panel), or the record's form. What the part says about its
// holder is drawn by the server for this viewer, so the merge does the rest.
// Any kind not known is ignored.
//
// ONE LINE OF READS. This script has at most ONE GET on its way. What is
// asked meanwhile is owed (`pending`) and coalesced: the list swallows the
// blocks asked beside it (it contains them), two asks for one part are one,
// and the record's form is its own part but goes through the same line. Reads
// are therefore drawn in the order they were sent, and a slower, older answer
// can never be drawn over a newer one (a list answer over a block's, or the
// reverse): that would show a colleague's old text on an old base and the
// next save of that card would be refused.
//
// AN ANSWER IS DRAWN ONLY IF IT IS THE NEWEST THING THIS TAB KNOWS:
// - a read that has not been sent yet is skipped when something newer was
//   asked for the same content (its part, or the list for a block); one on
//   the wire is drawn -- it is newer than the screen -- and the newer ask
//   goes out next;
// - a read waits until this tab's write queue is quiet (`quiet()`), and an
//   answer during whose flight this tab queued a write (`writeCount()`) is
//   dropped and asked for again: it was read before that write;
// - the list is not fetched or drawn while a block is being dragged, is
//   picked up by the keyboard or has a move that is not yet answered
//   (`admin--editor--blocks:moving`, true while ANY of them is open): it is
//   owed, and paid when the last one is over.
//
// A HIDDEN DOCUMENT FETCHES NOTHING; it owes the list and the record and pays
// once when it is seen. Whenever the subscription is confirmed (the first time
// and after every reconnect) the list and the record's form are fetched once
// as a CATCH-UP -- a signal sent while the socket was down was not heard --
// and a catch-up draws only what differs (`onlyChanged`, by
// `data-editing-version`): it must not close a menu the person has just
// opened or mount every editor again. A subscription that is REJECTED (the
// viewer's access ended) fetches the record once, so that its 404 says so.
//
// THE PART ANSWERS (`data-live-part`, `live/state`): "answered" once the
// subscription is confirmed or rejected AND that first read has been
// attempted -- drawn, dropped for a newer one, failed or timed out -- and
// "waiting" while the connection is down. A read has a timeout (`timeout`),
// a drawing that throws is reported and does not stop that. A FAILED read
// (nothing came back, a 5xx) is owed and asked again after `retry`, three
// times and growing; after that it waits for the next signal, connect or
// `visibilitychange`.
//
// The "Updated by" mark comes with a block's own read (`mark=1`). A block ask
// folded into a list ask is fetched with the mark after the list is drawn.
//
// WHAT IS NOT REPLACED: a form that holds unsaved changes (the write queue's
// own question) and a unit whose block has a menu or a dialog open (`busy`:
// a menu of its card or tile, a dialog inside it, the layout's link dialog or
// media picker for a field of it). Such a unit that is kept only for that is
// fetched again when the menu or dialog closes (a listener, no polling). A
// unit someone else moved while it holds unsaved text stays where it is and
// the list is fetched again once its form is no longer unsaved (`moved`).
//
// A 404 of the record or the list means the record is gone or no longer the
// viewer's to read: the editor says so in the header's notice area (appended;
// a "Changed elsewhere" bar already there stays) and offers the way back. One
// block's 404 may only be a block this page never had: the list says which.
//
// The editors carry `turbo-cache-control: no-cache`, so no snapshot of one is
// kept and nothing this script wrote into the page (marks, `data-editing-gone`,
// the missing bar, the part's word) comes back with Back.
//
// It writes nothing, sends nothing through the write queue and uses no Turbo
// request, visit, frame or stream (`test/system/admin/editing_live_test.rb`).
const BACKOFF = [ 1, 3, 9 ]
const MENU = "[data-admin--ui--menu-target~='panel']:not([hidden])"

export default class extends Controller {
  static targets = [ "missing" ]
  static values = {
    kind: String, id: String, blocksUrl: String, blockUrl: String, recordUrl: String,
    notice: { type: Number, default: 6000 }, timeout: { type: Number, default: 10000 }, retry: { type: Number, default: 1000 }
  }

  connect() {
    this.pending = new Map()
    this.owed = new Map()
    this.failures = new Map()
    this.timers = new Set()
    this.watchers = new Map()
    this.waitingForMoved = null
    this.running = false
    this.moving = false
    this.busy = null
    this.kept = null
    const listener = Object.assign((signal) => this.heard(signal), {
      connected: () => this.catchUp().then(() => { if (this.element.isConnected && this.stop && this.stop.up !== false) this.say("answered") }),
      rejected: () => this.want("record").then(() => { if (this.element.isConnected) this.say("answered") }),
      disconnected: () => this.say("waiting")
    })
    // One order and the id as a string: the pool's key is the params' JSON.
    this.stop = listen({ channel: "Editing::Channel", type: this.kindValue, id: String(this.idValue) }, listener)
    if (this.stop.up) listener.connected()
    else if (this.stop.rejected) listener.rejected()
    else if (this.stop.settled) this.say("answered")

    this.seen = () => { if (!document.hidden) this.pay() }
    this.moved = (event) => { this.moving = event.detail.moving; if (!this.moving) this.pay() }
    this.asked_for = (event) => this.refresh(event.detail)
    document.addEventListener("visibilitychange", this.seen)
    this.element.addEventListener("admin--editor--blocks:moving", this.moved)
    this.element.addEventListener("admin--editing--hold:refresh", this.asked_for)
  }

  disconnect() {
    this.stop?.()
    document.removeEventListener("visibilitychange", this.seen)
    this.element.removeEventListener("admin--editor--blocks:moving", this.moved)
    this.element.removeEventListener("admin--editing--hold:refresh", this.asked_for)
    this.timers.forEach(clearTimeout)
    this.watchers.forEach((watcher) => watcher.stop())
    this.watchers.clear()
    settle(document.body)
  }

  say(word) {
    this.element.setAttribute("data-live-part", word)
    settle(document.body)
  }

  heard(signal) {
    if (signal.origin === TAB) return
    if (signal.kind === "holder") {
      // The hold script hears it first (a request to hand over, a block taken),
      // then the part is fetched as before.
      const subject = signal.content_block_id ? `block-${signal.content_block_id}` : "record"
      this.dispatch("holder", { detail: { subject, reason: signal.reason } })
      return this.want(signal.content_block_id ? `block:${signal.content_block_id}` : "record")
    }
    if (signal.kind !== "content") return
    if (signal.reason === "gone") return this.want("record")
    if (signal.reason === "structure") return this.want(this.hasBlocksUrlValue ? "blocks" : "record")
    this.want(signal.content_block_id ? `block:${signal.content_block_id}` : "record", { mark: true })
  }

  // The hold script asks for a subject's part again: a hold that lapsed, a
  // refused form that is discarded (`discard`: its unit may be replaced
  // although its form is not clean).
  //
  // A DISCARD is a promise to show the server's version whatever it says about
  // that version: the units of the subject (a block in a section has two, its
  // tile's panel and its card) are marked, and their version is cleared, so
  // that no catch-up (`onlyChanged`, which an ask made while the document was
  // hidden has become) can find them "unchanged" and keep the refused text.
  //
  // `notice` asks for a deleted block's notice instead (`notice:<id>`, drawn
  // by `admin--editing--hold` from the `notice` event): it goes through the
  // same line, with the same retries, and while the document is hidden it is
  // owed. `waits`, when given, gets the promise of the ask, so that the
  // hold script can tell when it has been dealt with.
  refresh({ subject, discard = false, notice = false, waits = null }) {
    if (discard) {
      for (const unit of this.element.querySelectorAll(`[data-editing-unit][data-editing-subject="${CSS.escape(subject)}"]`)) {
        unit.setAttribute("data-editing-discard", "true")
        unit.removeAttribute("data-editing-version")
      }
    }
    const id = subject.replace("block-", "")
    const asked = this.want(notice ? `notice:${id}` : (subject === "record" ? "record" : `block:${id}`))
    waits?.push(asked)
    return asked
  }

  // The list and the record's form, drawing only what differs.
  catchUp() {
    return Promise.all([ this.hasBlocksUrlValue ? this.want("blocks", { onlyChanged: true }) : null, this.want("record", { onlyChanged: true }) ])
  }

  // Asks for a part. Answers a promise that is kept when the ask has been
  // dealt with: drawn, dropped for a newer one, owed or failed.
  want(part, options = {}) {
    if (part === "blocks" && !this.hasBlocksUrlValue) part = "record"
    if (document.hidden) {
      this.owe("blocks", { onlyChanged: true }); this.owe("record", { onlyChanged: true })
      if (part.startsWith("notice:")) this.owe(part, options)
      return Promise.resolve()
    }
    if (this.moving && part !== "record") { this.owe(part, options); return Promise.resolve() }
    return new Promise((resolve) => this.ask(part, options, [ resolve ]))
  }

  owe(part, options = {}) {
    if (part === "blocks" && !this.hasBlocksUrlValue) part = "record"
    this.owed.set(part, this.merged(this.owed.get(part), { options }).options)
  }

  pay() {
    if (document.hidden || this.moving) return
    const owed = [ ...this.owed ]
    this.owed.clear()
    owed.forEach(([ part, options ]) => this.want(part, options))
  }

  // Puts an ask in the line. The list swallows the blocks asked beside it, and
  // a block asked while the list is waiting is covered by it.
  ask(part, options, waiters) {
    const entry = { options, waiters }
    if (part.startsWith("block:") && this.pending.has("blocks")) {
      this.join("blocks", this.folded(part, entry))
    } else if (part === "blocks") {
      for (const key of [ ...this.pending.keys() ].filter((each) => each.startsWith("block:"))) {
        this.join("blocks", this.folded(key, this.pending.get(key)))
        this.pending.delete(key)
      }
      this.join("blocks", entry)
    } else {
      this.join(part, entry)
    }
    this.pump()
  }

  // A block's ask folded into the list's. The list answer carries no "Updated
  // by" mark, so a block that was to be marked is remembered (`marked`) and
  // fetched with `mark=1` after the list is drawn.
  folded(part, entry) {
    const marked = entry.options.mark ? [ part.slice("block:".length) ] : []
    return { ...entry, options: { ...entry.options, mark: false, marked } }
  }

  join(part, entry) {
    this.pending.set(part, this.merged(this.pending.get(part), entry))
  }

  // Two asks for one part: it replaces if either does, marks if either does.
  merged(first, second) {
    if (!first) return { options: { ...second.options }, waiters: second.waiters || [] }
    const a = first.options || first
    const b = second.options
    return {
      options: { onlyChanged: Boolean(a.onlyChanged && b.onlyChanged), mark: Boolean(a.mark || b.mark), marked: [ ...new Set([ ...(a.marked || []), ...(b.marked || []) ]) ] },
      waiters: [ ...(first.waiters || []), ...(second.waiters || []) ]
    }
  }

  async pump() {
    if (this.running) return
    this.running = true
    try {
      while (this.pending.size > 0 && this.element.isConnected) {
        const [ part, entry ] = this.pending.entries().next().value
        this.pending.delete(part)
        await this.send(part, entry)
      }
    } finally {
      this.running = false
    }
  }

  // Whether something newer was asked for the content `part` covers.
  covered(part) {
    return this.pending.has(part) || (part.startsWith("block:") && this.pending.has("blocks"))
  }

  handOn(part, entry) {
    if (part.startsWith("block:") && this.pending.has("blocks")) this.join("blocks", this.folded(part, entry))
    else this.join(part, entry)
  }

  settled(entry) {
    entry.waiters.forEach((resolve) => resolve())
  }

  async send(part, entry) {
    await quiet()
    if (!this.element.isConnected) return
    if (this.covered(part)) return this.handOn(part, entry)
    if (document.hidden || (this.moving && part !== "record")) { this.owe(part, entry.options); return this.settled(entry) }

    const writes = writeCount()
    const answer = await get(this.urlFor(part, entry.options), { timeout: this.timeoutValue })
    if (!this.element.isConnected) return
    // An answer on the wire is NOT dropped because its part was asked again
    // meanwhile: in a single line it is newer than the screen, and the newer
    // ask goes out next. (A colleague saving every second would otherwise
    // starve the block.) Only this tab's own write makes it too old.
    if (writeCount() !== writes) { this.handOn(part, entry); return }
    if (document.hidden || (this.moving && part !== "record")) { this.owe(part, entry.options); return this.settled(entry) }
    if (answer.status === 0 || answer.status >= 500 || (answer.status >= 400 && answer.status !== 404 && answer.status !== 410)) {
      this.failed(part, entry.options)
      return this.settled(entry)
    }
    this.failures.delete(part)
    try {
      this.draw(part, answer, entry.options)
    } catch (error) {
      console.error(error)
    }
    // What a folded ask wanted marked.
    ;(entry.options.marked || []).forEach((id) => this.want(`block:${id}`, { mark: true }))
    this.settled(entry)
  }

  // Owed, and asked again after a growing wait, three times; then it waits
  // for the next signal, connect or `visibilitychange`.
  failed(part, options) {
    this.owe(part, options)
    const count = this.failures.get(part) || 0
    this.failures.set(part, count + 1)
    if (count >= BACKOFF.length) return
    const timer = setTimeout(() => {
      this.timers.delete(timer)
      if (!this.owed.has(part)) return
      const owed = this.owed.get(part)
      this.owed.delete(part)
      this.want(part, owed)
    }, BACKOFF[count] * this.retryValue)
    this.timers.add(timer)
  }

  urlFor(part, { mark = false } = {}) {
    if (part === "blocks") return this.blocksUrlValue
    if (part === "record") return this.recordUrlValue
    const url = new URL(this.blockUrlValue.replace(":block_id", part.slice(part.indexOf(":") + 1)), window.location.origin)
    if (mark) url.searchParams.set("mark", "1")
    return url.toString()
  }

  draw(part, answer, { onlyChanged = false } = {}) {
    // A deleted block's notice is the answer's body, drawn by the hold script.
    if (part.startsWith("notice:")) return this.dispatch("notice", { detail: { blockId: part.slice("notice:".length), status: answer.status, text: answer.text } })
    if (answer.status === 404) return part.startsWith("block:") ? this.want("blocks") : this.gone()
    this.busy = this.busySubjects()
    this.kept = new Set()
    try {
      this.drawFragment(part, answer, onlyChanged)
    } finally {
      this.pruneWatchers()
      this.watchKept(this.kept, this.busy)
      this.busy = null
      this.kept = null
    }
  }

  drawFragment(part, answer, onlyChanged) {
    if (part === "blocks") {
      if (!answer.fragment) return
      const list = this.element.querySelector("#content-blocks-list")
      const before = new Set(list.querySelectorAll("[data-editing-gone]"))
      const result = anchored(list, () => mergeList(list, answer.fragment, { unsaved: this.unsaved, onlyChanged, hold: this.holdPart }))
      result.gone.filter((unit) => !before.has(unit)).forEach((unit) => this.dispatch("deleted", { detail: { blockId: unit.dataset.blockId, unit } }))
      if (result.moved.length > 0) this.fetchAgainWhenSaved(result.moved)
      return this.dispatch("merged", { detail: { part, replaced: [], ...result } })
    }
    if (part === "record") {
      if (!answer.fragment) return
      const result = mergeUnits(this.element, answer.fragment, { unsaved: this.unsaved, onlyChanged, hold: this.holdPart })
      if (result.moved.length > 0) this.fetchAgainWhenSaved(result.moved)
      if (result.missing && this.hasBlocksUrlValue) this.want("blocks")
      return this.dispatch("merged", { detail: { part, gone: [], ...result } })
    }
    // One block. 204: a section, whose card holds other blocks' forms. 410:
    // deleted since. Either way the list says what is true now.
    if (answer.status === 204 || answer.status === 410) return this.want("blocks")
    if (!answer.fragment) return
    const result = anchored(this.element, () => mergeUnits(this.element, answer.fragment, { unsaved: this.unsaved, onlyChanged, hold: this.holdPart }))
    if (result.moved.length > 0) this.fetchAgainWhenSaved(result.moved)
    if (result.missing) this.want("blocks")
    result.replaced.forEach((unit) => this.fade(unit.querySelector("[data-editing-mark]")))
    this.dispatch("merged", { detail: { part, gone: [], ...result } })
  }

  // A block that holds unsaved text was moved by someone else and stays where
  // it is (`moved`). Once none of those forms is unsaved any more, the list
  // is fetched again, once, with no notice: the block takes its place. A form
  // that stays unsaved costs one in-page check a second and no request.
  async fetchAgainWhenSaved(units) {
    if (this.waitingForMoved) { units.forEach((unit) => this.waitingForMoved.add(unit)); return }
    const waiting = this.waitingForMoved = new Set(units)
    for (;;) {
      await quiet()
      if (!this.element.isConnected || this.waitingForMoved !== waiting) return
      const left = [ ...waiting ].filter((unit) => unit.isConnected && holds(unit, this.unsaved))
      if (left.length === 0) break
      waiting.clear()
      left.forEach((unit) => waiting.add(unit))
      await new Promise((resolve) => { const timer = setTimeout(() => { this.timers.delete(timer); resolve() }, 1000); this.timers.add(timer) })
    }
    this.waitingForMoved = null
    this.want(this.hasBlocksUrlValue ? "blocks" : "record")
  }

  // The write queue's own question, put to a form the merge would replace --
  // and whether its block has a menu or a dialog open (`busy`). A unit whose
  // text the person has discarded is nobody's to keep.
  unsaved = (form) => {
    if (form.closest("[data-editing-discard]")) return false
    const autosave = this.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave")
    if (autosave && (!autosave.clean() || autosave.outstanding() || !autosave.unchanged())) return true
    const subject = (form.closest("[data-editing-unit]") || form).dataset.editingSubject
    const busy = this.busy || this.busySubjects()
    if (subject && busy.has(subject)) { this.kept?.add(subject); return true }
    return false
  }

  // A PART (a section's tile) is replaced like anything that holds no unsaved
  // form -- except while its own menu or delete dialog is open (`busy`): the
  // merge's `hold` option, the smallest change to how a part is judged. It is
  // refreshed when that closes, like a unit.
  holdPart = (part) => {
    const subject = part.dataset.editingSubject
    const busy = this.busy || this.busySubjects()
    if (subject && busy.has(subject)) { this.kept?.add(subject); return true }
    return false
  }

  // The blocks (by subject) that have something open that the merge must not
  // take from under the person: a menu panel shown, a dialog open inside the
  // editor (a tile's menu and its delete dialog belong to the block the tile
  // stands for), and the layout's own dialogs -- the rich-text link/image
  // dialog and the media picker, which stand outside every unit and know
  // which field they work for (`session.opener`, `opener`). Answers a Map of
  // subject => the elements whose closing frees it.
  busySubjects() {
    const busy = new Map()
    const add = (element, near) => {
      const subject = near?.closest?.("[data-editing-subject]")?.dataset.editingSubject
      if (subject && this.element.contains(near)) busy.set(subject, [ ...(busy.get(subject) || []), element ])
    }
    this.element.querySelectorAll(MENU).forEach((panel) => add(panel, panel))
    this.element.querySelectorAll("dialog[open]").forEach((dialog) => add(dialog, dialog))
    for (const controller of this.application.controllers) {
      if (controller.identifier === "admin--rich-text--dialog" && controller.session?.opener) {
        const open = Object.values(controller.dialogs || {}).find((dialog) => dialog.open)
        if (open) add(open, controller.session.opener)
      } else if (controller.identifier === "admin--media--picker" && controller.element.open && controller.opener) {
        add(controller.element, controller.opener)
      }
    }
    return busy
  }

  // A unit kept ONLY because a menu or dialog was open is fetched again when
  // the last of them closes, however many follow one another (the media
  // picker closes and the alt-text dialog opens): a listener on each element
  // that holds it, no polling. A watcher is on elements in the document; one
  // whose elements have left it is ended at once and the block fetched again
  // (`pruneWatchers`, after every drawing).
  watchKept(subjects, busy) {
    for (const subject of subjects) {
      if (this.watchers.has(subject)) continue
      const elements = busy.get(subject) || []
      const done = () => {
        this.watchers.get(subject)?.stop()
        this.watchers.delete(subject)
        // A moment later: the dialog's own `close` handlers apply what the person did first.
        const timer = setTimeout(() => {
          this.timers.delete(timer)
          const now = this.busySubjects()
          if (now.has(subject)) return this.watchKept(new Set([ subject ]), now)
          this.want(this.partOf(subject))
        }, 0)
        this.timers.add(timer)
      }
      const cleanups = elements.map((element) => {
        if (element.matches("dialog")) {
          element.addEventListener("close", done, { once: true })
          return () => element.removeEventListener("close", done)
        }
        const observer = new MutationObserver(() => { if (element.hidden || !element.isConnected) done() })
        observer.observe(element, { attributes: true, attributeFilter: [ "hidden" ] })
        return () => observer.disconnect()
      })
      this.watchers.set(subject, { elements, stop: () => cleanups.forEach((stop) => stop()) })
    }
  }

  partOf(subject) {
    return subject === "record" ? "record" : `block:${subject.replace("block-", "")}`
  }

  // A watcher whose elements have all left the document can never hear them
  // close: ended, and the block fetched again.
  pruneWatchers() {
    for (const [ subject, watcher ] of [ ...this.watchers ]) {
      if (watcher.elements.some((element) => element.isConnected)) continue
      watcher.stop()
      this.watchers.delete(subject)
      this.want(this.partOf(subject))
    }
  }

  // "Updated by ..." stays for `notice` and fades over 200ms (handoff 10);
  // with reduced motion it goes at once.
  fade(mark) {
    if (!mark) return
    const later = (act, ms) => { const timer = setTimeout(() => { this.timers.delete(timer); act() }, ms); this.timers.add(timer) }
    later(() => {
      if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return mark.remove()
      mark.classList.add("admin-editing-mark--leaving")
      later(() => mark.remove(), 200)
    }, this.noticeValue)
  }

  // The record is in the trash, deleted or no longer this viewer's: said once,
  // in the header's notice area, with the way back; the stream is let go, what
  // was waiting is dropped, and the part answers. `#editor-notice` is shared with the 409's "Changed
  // elsewhere" bar: this APPENDS to it. (A later 409 replaces the area's
  // content, but a record that is gone refuses a save with a 404, not a 409.)
  gone() {
    this.stop?.()
    this.stop = null
    this.pending.clear()
    this.owed.clear()
    this.say("answered")
    const notice = document.getElementById("editor-notice")
    if (notice && this.hasMissingTarget && !notice.querySelector("[data-editing-missing]")) notice.append(this.missingTarget.content.cloneNode(true))
  }
}
