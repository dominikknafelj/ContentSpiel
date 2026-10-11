import { Controller } from "@hotwired/stimulus"
import { listen, TAB } from "live/connection"
import { settle } from "live/state"
import { quiet, writeCount } from "saving/queue"
import { get } from "editing/requests"
import { anchored, holds, mergeList, mergeUnits } from "editing/merge"

// The event the hold script sends (`detail: { subject, discard }`). Written in
// parts until that controller exists: `test/lib/source_layout_test.rb` holds
// that every identifier written in the app has a controller file.
const HOLD_REFRESH = [ "admin", "editing", "hold:refresh" ].join("--")

// LIVE REFRESH of an open page or post editor (live-editing spec §3.2). On
// the element `Admin::EditorScreen::LiveRegionComponent` renders.
//
// It hears, on the record's stream (`Editing::Channel`), THAT something
// changed -- a kind, a block's id, a reason -- and fetches that part with a
// plain GET through the read scope, as its viewer may see it now: one block,
// the block list (`structure`), or the record's own form. What comes back is
// handed to `editing/merge`, which never replaces a form that holds unsaved
// changes. The tab that made the change skips its own signal (`origin`).
//
// AN ANSWER IS DRAWN ONLY IF IT IS THE NEWEST THING THIS TAB KNOWS:
// - each part has a number, and an answer whose number is not the part's
//   newest is dropped (two fetches of one part can overtake each other);
// - a fetch waits until this tab's write queue is quiet (`quiet()`), and an
//   answer during whose flight this tab queued a write (`writeCount()`) is
//   dropped and asked for again: it was read before that write;
// - the list is not fetched or drawn while a block is being dragged or is
//   picked up by the keyboard (`admin--editor--blocks:moving`): it is owed,
//   and paid when the move has been answered.
//
// A HIDDEN DOCUMENT FETCHES NOTHING; it owes everything and pays once when it
// is seen. Whenever the subscription is confirmed (the first time and after
// every reconnect) the list and the record's form are fetched once: a signal
// sent while the socket was down was not heard.
//
// A 404 means the record is gone or no longer the viewer's to read: the
// editor says so in the header's notice area and offers the way back.
//
// It writes nothing, sends nothing through the write queue and uses no Turbo
// request, visit, frame or stream (`test/system/admin/editing_live_test.rb`).
export default class extends Controller {
  static targets = [ "missing" ]
  static values = { kind: String, id: String, blocksUrl: String, blockUrl: String, recordUrl: String, notice: { type: Number, default: 6000 } }

  connect() {
    this.asked = new Map()
    this.owed = new Set()
    this.timers = new Set()
    this.moving = false
    const listener = Object.assign((signal) => this.heard(signal), {
      connected: () => this.catchUp().then(() => { if (this.element.isConnected && this.stop?.up !== false) this.say("answered") }),
      rejected: () => this.say("answered"),
      disconnected: () => this.say("waiting")
    })
    // One order and the id as a string: the pool's key is the params' JSON.
    this.stop = listen({ channel: "Editing::Channel", type: this.kindValue, id: String(this.idValue) }, listener)
    if (this.stop.up) listener.connected()
    else if (this.stop.settled) this.say("answered")

    this.seen = () => { if (!document.hidden) this.pay() }
    this.moved = (event) => { this.moving = event.detail.moving; if (!this.moving) this.pay() }
    this.asked_for = (event) => this.refresh(event.detail)
    document.addEventListener("visibilitychange", this.seen)
    this.element.addEventListener("admin--editor--blocks:moving", this.moved)
    this.element.addEventListener(HOLD_REFRESH, this.asked_for)
  }

  disconnect() {
    this.stop?.()
    document.removeEventListener("visibilitychange", this.seen)
    this.element.removeEventListener("admin--editor--blocks:moving", this.moved)
    this.element.removeEventListener(HOLD_REFRESH, this.asked_for)
    this.timers.forEach(clearTimeout)
    settle(document.body)
  }

  say(word) {
    this.element.setAttribute("data-live-part", word)
    settle(document.body)
  }

  heard(signal) {
    if (signal.origin === TAB) return
    // `holder` signals (a reservation changed) are heard from Task 8 on; until
    // then, and for any kind not known yet, nothing is done.
    if (signal.kind !== "content") return
    if (signal.reason === "gone") return this.want("record")
    if (signal.reason === "structure") return this.want(this.hasBlocksUrlValue ? "blocks" : "record")
    this.want(signal.content_block_id ? `block:${signal.content_block_id}` : "record", { mark: true })
  }

  // The hold script asks for a subject's part again: a hold that lapsed, a
  // refused form that is discarded (`discard`: its unit may be replaced
  // although its form is not clean).
  refresh({ subject, discard = false }) {
    if (discard) document.querySelector(`[data-editing-unit][data-editing-subject="${CSS.escape(subject)}"]`)?.setAttribute("data-editing-discard", "true")
    this.want(subject === "record" ? "record" : `block:${subject.replace("block-", "")}`)
  }

  // Fetches the list and the record's form, and resolves once both have been
  // drawn (or dropped). The part says "answered" only then: a test (or a
  // person's script) that waits for it finds the screen as it will stay, not
  // about to be redrawn under its first click.
  catchUp() {
    return Promise.all([ this.hasBlocksUrlValue ? this.want("blocks") : null, this.want("record") ])
  }

  want(part, options = {}) {
    if (document.hidden) { this.owed.add("blocks").add("record"); return Promise.resolve() }
    if (this.moving && part !== "record") { this.owed.add(part); return Promise.resolve() }
    return this.fetch(part, options)
  }

  pay() {
    if (document.hidden || this.moving) return
    const owed = [ ...this.owed ]
    this.owed.clear()
    // The list holds every block: a block owed beside it needs no fetch of its own.
    owed.filter((part) => !(part.startsWith("block:") && owed.includes("blocks"))).forEach((part) => this.want(part))
  }

  async fetch(part, options = {}) {
    if (part === "blocks" && !this.hasBlocksUrlValue) return
    const number = (this.asked.get(part) || 0) + 1
    this.asked.set(part, number)
    const newest = () => this.asked.get(part) === number && this.element.isConnected

    await quiet()
    if (!newest()) return
    const writes = writeCount()
    const answer = await get(this.urlFor(part, options))
    if (!newest()) return
    if (writeCount() !== writes) return this.fetch(part, options)
    if (document.hidden || (this.moving && part !== "record")) { this.owed.add(part); return }
    this.draw(part, answer)
  }

  urlFor(part, { mark = false } = {}) {
    if (part === "blocks") return this.blocksUrlValue
    if (part === "record") return this.recordUrlValue
    const url = new URL(this.blockUrlValue.replace(":block_id", part.slice("block:".length)), window.location.origin)
    if (mark) url.searchParams.set("mark", "1")
    return url.toString()
  }

  draw(part, answer) {
    // A 404 of the record or the list means the record is gone. One block's
    // 404 may only be a block this page never had: the list says which.
    if (answer.status === 404) return part.startsWith("block:") ? this.want("blocks") : this.gone()
    if (part === "blocks") {
      if (!answer.fragment) return
      const list = this.element.querySelector("#content-blocks-list")
      const result = anchored(list, () => mergeList(list, answer.fragment, { unsaved: this.unsaved }))
      result.gone.forEach((unit) => this.dispatch("deleted", { detail: { blockId: unit.dataset.blockId, unit } }))
      if (result.moved.length > 0) this.fetchAgainWhenSaved(result.moved)
      return this.dispatch("merged", { detail: { part, replaced: [], ...result } })
    }
    if (part === "record") {
      if (!answer.fragment) return
      return this.dispatch("merged", { detail: { part, gone: [], ...mergeUnits(this.element, answer.fragment, { unsaved: this.unsaved }) } })
    }
    // One block. 204: a section, whose card holds other blocks' forms. 410:
    // deleted since. Either way the list says what is true now.
    if (answer.status === 204 || answer.status === 410) return this.want("blocks")
    if (!answer.fragment) return
    const result = anchored(this.element, () => mergeUnits(this.element, answer.fragment, { unsaved: this.unsaved }))
    if (result.missing) return this.want("blocks")
    result.replaced.forEach((unit) => this.fade(unit.querySelector("[data-editing-mark]")))
    this.dispatch("merged", { detail: { part, gone: [], ...result } })
  }

  // A block that holds unsaved text was moved by someone else and stays where
  // it is (`moved` of `mergeList`). Once none of those forms is unsaved any
  // more, the list is fetched again, with no notice: the block takes its place.
  async fetchAgainWhenSaved(units) {
    if (this.waitingForMoved) { units.forEach((unit) => this.waitingForMoved.add(unit)); return }
    this.waitingForMoved = new Set(units)
    for (;;) {
      await quiet()
      if (!this.element.isConnected) return
      const left = [ ...this.waitingForMoved ].filter((unit) => unit.isConnected && holds(unit, this.unsaved))
      if (left.length === 0) break
      this.waitingForMoved = new Set(left)
      await new Promise((resolve) => { const timer = setTimeout(() => { this.timers.delete(timer); resolve() }, 1000); this.timers.add(timer) })
    }
    this.waitingForMoved = null
    this.want("blocks")
  }

  // The write queue's own question, put to a form the merge would replace --
  // and whether someone is in the middle of a dialog (the link dialog, the
  // media picker) or a menu of its unit. A unit whose text the person has
  // discarded is nobody's to keep.
  unsaved = (form) => {
    if (form.closest("[data-editing-discard]")) return false
    const unit = form.closest("[data-editing-unit]") || form
    if (unit.querySelector("dialog[open], [data-admin--ui--menu-target~='panel']:not([hidden])")) return true
    const autosave = this.application.getControllerForElementAndIdentifier(form, "admin--saving--autosave")
    return Boolean(autosave) && (!autosave.clean() || autosave.outstanding() || !autosave.unchanged())
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
  // in the header's notice area, with the way back; nothing is fetched again.
  gone() {
    this.stop?.()
    const notice = document.getElementById("editor-notice")
    if (notice && this.hasMissingTarget && !notice.querySelector("[data-editing-missing]")) notice.replaceChildren(this.missingTarget.content.cloneNode(true))
  }
}
