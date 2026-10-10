import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"
import { TAB, listen } from "live/connection"
import { json } from "notes/json"
import { report } from "live/state"
import { hold, mergeGone, mergeList, mergeThread, scrollerOf } from "notes/merge"

// Live delivery of notes, the RECORD'S side (notes spec §6): a record's
// threads and its list kept current while someone reads or types in them,
// and the answers to the tab's own buttons merged the same way. Lives on
// <body>, so the parts that show one record's notes (its `record` targets)
// are found wherever they are drawn. A signal over the cable says only THAT
// something changed (`Notes::Signals`: a kind and ids); this controller then
// fetches the part again through the same scoped GET the page used on load,
// so what a tab can show is always what its viewer may read. The connection
// is `live/connection`'s (the consumer, the shared subscriptions, the tab's
// id and the socket's closing when a Turbo visit leaves CS Studio): this
// controller listens through it (`listen`).
//
// The PERSON'S side -- the person's stream, the sidebar's count, the
// dashboard's cards, the toasts and their bursts -- is `admin--notes--inbox`,
// beside this controller on <body>. It asks this one whether the person is
// looking at a thread (`watched`, `watching`), and that is all the two say to
// each other.
//
// THE SUBSCRIPTIONS. `Notes::RecordChannel`, one per `record` target (an
// editor's drawer, the media panel's notes, the mind graph's card): a thread
// of that record changed, or went with a deleted block.
//
// REFRESHING WITHOUT LOSING WORK (§6.3). What is READ is replaced; what is
// TYPED is never touched.
// The rule has one owner, `notes/merge` (`mergeList`, `mergeThread`,
// `mergeGone`), whose header says what counts as typed and how a list and
// a thread are merged; `redrawList`, `redrawThread` and `gone` here call it
// and do what is not the view's business. What this controller decides is
// WHETHER a part is fetched:
// - A thread that is gone and holds no typed text: the frame goes to the
//   list (`gone`).
// - A drawer that is closed gets its counts only (`data-notes-counts-url`,
//   handed to `admin--notes--drawer#refreshCounts`): fetching a thread is what marks
//   it read, and nobody is reading a closed drawer. It is remembered as
//   stale and fetched when it is opened again. The same goes for a THREAD
//   in a document that is hidden (another tab is in front, the window is
//   minimised): its GET would read the note on the person's behalf, so it
//   gets the counts, the toast is raised, the delivery stays unread, and the
//   thread is fetched when the document is visible again (`visible`). A
//   list is fetched hidden or not: reading a list reads nothing. A part that
//   draws itself (the graph's card) hears `admin--notes--live:changed` on its
//   element.
// Signals in a burst are one fetch per part per 500 ms, and one request per
// part is out at a time: a signal that comes while one is out leads to
// exactly one more after it, so two answers can never land out of order. A
// refresh is this file's own `fetch`: it is no Turbo request, so it is never
// held by the write queue and never enters it.
//
// THIS TAB'S OWN WRITES. Every notes write the tab makes says which tab it is
// (`X-Notes-Tab`: `tag`, on the frame's Turbo forms and "Mark all read"; the
// graph's card reads the id from `data-notes-tab` on <body>), the server
// echoes it as the signal's `origin`, and a signal with this tab's own
// `origin` is ignored: the write's answer has drawn the change already. The
// header goes on WRITES only. A thread's GET marks deliveries read, and the
// `inbox` signal that follows must come back to this tab without an origin,
// because the sidebar's count is outside the frame that GET redrew.
//
// THE ANSWER TO ONE OF THIS TAB'S OWN BUTTONS is the whole thread view (a
// 303 to it, or the view again with its reason), and Turbo would draw it over
// the frame: an edit form open on ANOTHER message would close and its text be
// lost, the reply field be drawn again. So when a form of the thread was sent
// (a reaction, Pin, Notify, Resolve or Reopen, a reply) and the answer is the
// same thread's view, it is merged exactly as a live refresh is
// (`turbo:before-frame-render` on the notes frame, `answered`): the messages
// part is replaced around a message someone is working in, Resolve / Reopen
// is swapped, the reply part is left alone -- unless the reply's own composer
// is what was sent, whose part is then the answer's: empty after a note that
// went through, or with the text and the reason after one that was refused.
// No "NEW" divider for it: nothing arrived that this person did not just do.
// The frame is drawn as it came, as before, when the answer is another view
// (the list, another thread, "This note is gone"), when what was sent is the
// form of the message being worked in (Save of an edit, the delete's
// confirmation, a chip beside the question): its answer is that message as it
// now is; and for a link (Edit, Delete, Cancel, Back), which asks for exactly
// that. This is where the frame is, not where the cable is: the hook is on
// the document, so it serves the drawer, the media panel and the notes page of
// a record alike, with or without a socket.
//
// THE SOCKET. When it drops, CS Studio works as without push; when it is
// back, every part is fetched once -- signals sent meanwhile were never
// received. What a session's end does to the socket: `live/connection`.
// `data-notes-live="connected"` on <body> says that every subscription of
// this page has been answered (confirmed, or rejected for a record the
// viewer may not read): a signal sent from then on is received. This
// controller says how the records' subscriptions stand, `admin--notes--inbox`
// how the person's does, and `live/state` puts the two together.
//
// NO PAGE REFRESH, NO MORPHING (decision D20): nothing here touches an editor
// form, the write queue or anything outside the notes parts.
const COALESCE_MS = 500
export default class extends Controller {
  static targets = [ "record" ]

  // Before the first target connects, which is before `connect`.
  initialize() {
    // How often Turbo has drawn each notes frame (`answered`).
    this.draws = new WeakMap()
    this.records = new Map()
    this.timers = new Map()
    this.stale = new WeakSet()
  }

  connect() {
    this.element.dataset.notesTab = TAB
    this.sync()
  }

  disconnect() {
    this.records.forEach((record) => record.stop())
    this.records.clear()
    this.timers.forEach((timer) => clearTimeout(timer))
    this.timers.clear()
  }

  recordTargetConnected(element) {
    const record = { dropped: false }
    const heard = (signal) => {
      if (signal?.kind !== "threads" || signal.origin === TAB) return
      this.soon(element, () => this.refresh(element, signal.thread_id ?? null))
    }
    const stop = listen({ channel: "Notes::RecordChannel", type: element.dataset.notesType, id: String(element.dataset.notesId) }, Object.assign(heard, {
      connected: () => {
        if (record.dropped) this.soon(element, () => this.refresh(element, null))
        record.dropped = false
        this.sync()
      },
      disconnected: () => {
        record.dropped = true
        this.sync()
      },
      rejected: () => this.sync()
    }))
    this.records.set(element, Object.assign(record, { stop }))
    this.sync()
  }

  recordTargetDisconnected(element) {
    this.records.get(element)?.stop()
    this.records.delete(element)
    clearTimeout(this.timers.get(element))
    this.timers.delete(element)
    this.sync()
  }

  // `turbo:before-fetch-request` on the document: this tab's notes WRITES say
  // which tab they are, so the signal they cause can be ignored here.
  tag(event) {
    const { url, fetchOptions } = event.detail
    if (!fetchOptions || String(fetchOptions.method || "GET").toUpperCase() === "GET") return
    if (url?.pathname?.includes("/notes/")) fetchOptions.headers["X-Notes-Tab"] = TAB
  }

  // `turbo:before-fetch-request` on the document, as `tag`: what the notes
  // frame is about to be answered for. A form that was sent (the event's
  // target; the redirect that follows is no second request here), or nothing
  // for the frame's own navigation (a link that was followed: the target is
  // the frame), whose answer is drawn as it comes.
  //
  // A PREFETCH IS NEITHER. Prefetch is on in CS Studio: a pointer resting on
  // a link for a moment fetches it, with the LINK as the event's target and
  // `X-Sec-Purpose: prefetch` among its headers. It answers nothing the frame
  // asked for, so it leaves what was sent alone -- or resting on "All notes"
  // while Pin's answer was on its way would have that answer drawn in full,
  // over an open edit. Only a form inside the frame and the frame itself are
  // heard here; anything else changes nothing.
  asked(event) {
    const frame = event.target.closest?.("turbo-frame#notes")
    if (!frame) return
    const options = event.detail.fetchOptions
    if (options?.headers?.["X-Sec-Purpose"] === "prefetch") return
    const sends = String(options?.method || "GET").toUpperCase() !== "GET"
    if (event.target === frame && !sends) return void (this.sent = null)
    if (!sends || !(event.target instanceof HTMLFormElement)) return
    // What has the focus is noted now: Turbo disables the button that was
    // pressed for as long as its request is out, and a disabled button has
    // lost the focus by the time the answer is drawn.
    const view = frame.querySelector(":scope > [data-notes-view='thread']")
    this.sent = { frame, form: event.target, held: view ? hold(view) : null }
  }

  // `turbo:before-frame-render` on the document: see "THE ANSWER TO ONE OF
  // THIS TAB'S OWN BUTTONS" above.
  answered(event) {
    const frame = event.target
    if (frame.id !== "notes") return
    const sent = this.sent
    this.sent = null
    // Counted, drawn as it comes or merged: a live answer that was asked
    // for before this one is older than what is about to be on screen
    // (`fetchPart`).
    this.draws.set(frame, (this.draws.get(frame) || 0) + 1)

    const view = frame.querySelector(":scope > [data-notes-view='thread']")
    const answer = event.detail.newFrame.querySelector(":scope > [data-notes-view='thread']")
    const same = Boolean(view && answer && answer.dataset.noteThread === view.dataset.noteThread)
    // Drawn as it comes or merged, the same thread stays where it was read.
    if (same) this.keepPlace(event, frame, view)
    if (!sent || sent.frame !== frame) return
    if (!same || view.querySelector("[data-note-gone]")) return
    if (!view.querySelector(":scope > [data-note-part='messages']") || !view.querySelector(":scope > [data-note-part='reply']")) return
    // The form of a message being worked in: that message is what the answer redraws.
    if (sent.form.closest("[data-note-message]")?.querySelector("form[data-note-composer], [data-note-delete-question]")) return

    const reply = sent.form.matches("[data-note-part='reply'] form[data-note-composer]")
    // Resolve or Reopen: the empty form beside the composer's.
    const state = sent.form.matches("[data-note-part='reply'] > form:not([data-note-composer])")
    event.detail.render = () => this.redrawThread(frame, view, answer, null, { own: true, reply, state, held: sent.held })
  }

  // The same thread drawn again by Turbo itself (Edit, Delete or Cancel in a
  // message's menu, a saved edit): where its messages have a scroller of
  // their own (the drawer and the sheet, decision 35) that scroller is a new
  // element afterwards and would start at its top, far from the message the
  // person just pressed something on. Its place is put back inside the
  // render, so nothing is painted in between. Where the thread is in the
  // flow, what scrolls is outside the frame and stays by itself.
  keepPlace(event, frame, view) {
    const scroller = scrollerOf(view)
    if (!view.contains(scroller)) return

    const top = scroller.scrollTop
    const draw = event.detail.render
    event.detail.render = (current, next) => {
      draw(current, next)
      const now = frame.querySelector(":scope > [data-notes-view='thread']")
      if (now) scrollerOf(now).scrollTop = top
    }
  }

  // `admin--notes--drawer:opened`: a drawer that was closed while its record changed
  // is fetched now. A task later, when `admin--notes--drawer#show` has either left
  // the frame as it is or sent it somewhere (which `refresh` waits for, and
  // `fresh` then says is no longer stale).
  shown() {
    this.recordTargets.forEach((element) => {
      if (this.stale.has(element)) this.soon(element, async () => { if (this.stale.has(element)) await this.refresh(element, null) }, 0)
    })
  }

  // `turbo:frame-load` on the document: the notes frame of a record was
  // drawn by Turbo itself, from an answer of now.
  fresh(event) {
    if (event.target.id !== "notes") return
    const element = this.recordTargets.find((record) => record.contains(event.target))
    if (element) this.stale.delete(element)
  }

  // `visibilitychange` on the document: a thread that changed while nobody
  // could see it is fetched now, which is also what reads it.
  visible() {
    if (document.hidden) return
    this.recordTargets.forEach((element) => {
      if (this.stale.has(element) && !element.hidden) this.soon(element, async () => { if (this.stale.has(element)) await this.refresh(element, null) }, 0)
    })
  }

  // --- the socket -------------------------------------------------------------------

  // Whether every record subscription of this page has been answered: this
  // controller's half of `data-notes-live` (`live/state`; the person's
  // subscription is `admin--notes--inbox`'s half).
  sync() {
    report(this.element, "records", [ ...this.records.values() ].every((record) => record.stop.settled))
  }

  // One run per key per COALESCE_MS, at the end of the burst's first window.
  // A refresh that fails (the network, a server error) is no error of the
  // page's: the part stays as it was and the next signal fetches it again.
  soon(key, run, delay = COALESCE_MS) {
    if (this.timers.has(key)) return
    this.timers.set(key, setTimeout(() => {
      this.timers.delete(key)
      Promise.resolve().then(run).catch((error) => console.warn("notes: a live refresh failed", error))
    }, delay))
  }

  // --- a record's notes -----------------------------------------------------------

  // One request per part at a time. A signal that comes while one is out is
  // not a second request beside it -- whose answer could land first and be
  // drawn over by the older one -- but exactly one more, after it.
  async refresh(element, threadId) {
    const record = this.records.get(element)
    if (!record || !element.isConnected) return
    if (record.out) return void (record.again = true)

    record.out = true
    try {
      await this.fetchPart(element, record, threadId)
    } finally {
      record.out = false
      const again = record.again
      record.again = false
      if (again && this.records.get(element) === record) this.soon(element, () => this.refresh(element, null), 0)
    }
  }

  async fetchPart(element, record, threadId) {
    element.dispatchEvent(new CustomEvent("admin--notes--live:changed", { detail: { threadId } }))

    const frame = element.querySelector("turbo-frame#notes")
    // A frame that was never asked for anything (a drawer never opened) has
    // no view and no address: counts only.
    const view = frame?.hasAttribute("src") ? frame.querySelector("[data-notes-view]") : null
    // Nobody is looking: a closed drawer, or a thread in a hidden document.
    // The counts, and the part again when someone is (`shown`, `visible`).
    if (!view || element.hidden || (view.dataset.notesView === "thread" && document.hidden)) {
      if (view) this.stale.add(element)
      return this.refreshCounts(element)
    }
    // Turbo is fetching this frame (a row was followed, a note was sent):
    // its answer may be older than the signal. Once it is in.
    if (frame.hasAttribute("busy")) return void this.soon(element, () => this.refresh(element, threadId))

    const drawn = this.draws.get(frame) || 0
    const response = await fetch(this.address(frame, view), { headers: { Accept: "text/html", "Turbo-Frame": "notes" } })
    // Signed out, the record out of reach: nothing to draw, and nothing said.
    const answer = response.ok ? new DOMParser().parseFromString(await response.text(), "text/html").querySelector("turbo-frame#notes > [data-notes-view]") : null
    // OLDER THAN WHAT IS ON SCREEN. `busy` was asked before the fetch only:
    // while this was out the person sent a note, or pressed a button, and
    // that answer has been drawn (a merged one leaves the view element in
    // place, so the check below does not see it) or is on its way. This
    // answer may have left before that write was saved; drawn, it would
    // take the person's own note off the screen, and the tab ignores its
    // own signal, so nothing would bring it back. Dropped, and asked for
    // again: the signal that led here may be newer than the write.
    if (frame.hasAttribute("busy") || (this.draws.get(frame) || 0) !== drawn) return void this.soon(element, () => this.refresh(element, threadId))
    // No answer to draw: a part that was stale stays stale. Or the answer is
    // nobody's any more: the part left and came back (another subscription),
    // or Turbo drew the frame while this was out, from a request made later.
    if (!answer || this.records.get(element) !== record || !element.isConnected || frame.querySelector("[data-notes-view]") !== view) return

    this.stale.delete(element)
    if (view.dataset.notesView === "list") this.redrawList(view, answer)
    else this.redrawThread(frame, view, answer, response.url)
  }

  // Where the view on screen is fetched from: the frame's own address, which
  // Turbo keeps current. A thread is asked for without `edit` and `delete`
  // (an open form of this tab is kept as it is, never fetched again); a
  // list with a new-note field is asked for with it, so the answer has the
  // field's place.
  address(frame, view) {
    const url = new URL(frame.getAttribute("src"), window.location.origin)
    url.pathname = url.pathname.replace(/\/threads\/\d+$/, "")
    if (view.dataset.notesView === "thread") {
      url.pathname = `${url.pathname}/threads/${encodeURIComponent(view.dataset.noteThread)}`
      url.searchParams.delete("edit")
      url.searchParams.delete("delete")
      // The message a reaction was given to, which the answer to that press
      // drew its fold open for: asked for again with every refresh it would
      // open a fold the reader has closed since.
      url.searchParams.delete("shown")
    } else {
      const subject = view.querySelector(":scope > #notes-new input[name='subject']")?.value
      if (subject && !url.searchParams.has("compose")) url.searchParams.set("compose", subject)
      // "This note is gone" was said by the answer that brought the list; a
      // refresh that asked with it again would put the status line back,
      // and have it announced, with every signal.
      url.searchParams.delete("notice")
    }
    return url.pathname + url.search
  }

  // The three below are the controller's side of the merge (`notes/merge`,
  // which owns the rule and every change inside the view): each hands the
  // view and the answer over, with the page's translator for what the merge
  // says, and does the rest itself.
  redrawList(view, answer) {
    mergeList(view, answer)
  }

  // `own`, `reply`, `state` and `held` are `mergeThread`'s (`answered`
  // passes them; a live refresh passes none).
  redrawThread(frame, view, answer, url, options = {}) {
    const merged = mergeThread(view, answer, { ...options, t: (key, values) => messages(this.element).t(key, values) })
    if (merged?.gone) this.gone(frame, view, answer, url)
  }

  // The thread is no longer there: its GET answered the list. The record's
  // counts are the answer's. With nothing typed, the frame goes where that
  // answer came from (the list, which says "This note is gone"); typed text
  // stays, and `mergeGone` says in the view why it can't be sent.
  gone(frame, view, answer, url) {
    const counts = answer.querySelector("[data-admin--notes--drawer-target~='counts']")?.dataset.counts
    if (counts) this.notes?.refreshCounts(JSON.parse(counts))
    if (mergeGone(view, { t: (key, values) => messages(this.element).t(key, values) })) return

    const list = new URL(url, window.location.origin)
    frame.src = list.pathname + list.search
  }

  async refreshCounts(element) {
    const url = element.dataset.notesCountsUrl
    if (!url) return
    const counts = await json(url)
    if (counts && element.isConnected) this.notes?.refreshCounts(counts)
  }

  // `admin--notes--drawer`, on the same element.
  get notes() {
    return this.application.getControllerForElementAndIdentifier(this.element, "admin--notes--drawer")
  }

  // --- is the person looking at a thread ------------------------------------------------

  // `admin--notes--inbox:watching` on the document: `admin--notes--inbox`,
  // which raises the toasts, asks whether the person is looking at a thread.
  // The answer is written into the event's own `detail`, and `dispatchEvent`
  // is synchronous, so the asker reads it on its next line. Neither
  // controller holds the other: no outlet, no import.
  watched(event) {
    event.detail.watching = this.watching(event.detail.threadId)
  }

  // Whether the person is looking at that thread, THE ONE PREDICATE: it is
  // the view of a notes frame that is open here, in a document that is not
  // hidden. It is `detail.shown` of the delivery's event
  // (`admin--notes--inbox:delivery`), what keeps the toast away, and -- its
  // second half, in `fetchPart` -- what lets a thread be fetched at all. The
  // window's focus is not part of it.
  watching(threadId) {
    if (document.hidden) return false
    return this.recordTargets.some((element) => {
      const view = element.hidden ? null : element.querySelector("turbo-frame#notes > [data-notes-view='thread']")
      return Boolean(view) && view.dataset.noteThread === String(threadId) && !view.querySelector("[data-note-gone]")
    })
  }
}
