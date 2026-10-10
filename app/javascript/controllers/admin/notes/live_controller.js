import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"
import { TAB, listen, open } from "live/connection"
import { hold, mergeGone, mergeList, mergeThread, scrollerOf } from "notes/merge"
import { forgetDrafts } from "controllers/admin/notes/composer_controller"

// Live delivery of notes (notes spec §6). Lives on <body>. A signal over the
// cable says only THAT something changed (`Notes::Signals`: a kind and ids);
// this controller then fetches the part again through the same scoped GET the
// page used on load, so what a tab can show is always what its viewer may
// read. The connection is `live/connection`'s (the consumer, the shared
// subscriptions, the tab's id and the socket's closing when a Turbo visit
// leaves CS Studio): this controller listens through it (`listen`).
//
// TWO SUBSCRIPTIONS.
// - `Notes::PersonChannel`, once per tab. `delivery`: a delivery was written
//   for the viewer. The sidebar's count and, on the dashboard, the two cards
//   are fetched again; then that one delivery is FETCHED as data -- the
//   signal may have reached someone who has since lost the right to read the
//   record, and a refusal ends it there, with nothing said -- announced on
//   `document` (`admin--notes--live:delivery`) and raised as a toast. No toast
//   when the person is LOOKING AT that thread (`watching`, the one predicate:
//   it is the view of a notes frame of this tab, and the document is not
//   hidden -- the window's focus is not asked for, so two windows side by
//   side both stay live): the thread's own refresh shows the message and,
//   being the thread's GET, reads the delivery. `inbox`: deliveries of theirs
//   were read or removed elsewhere; only the count and the cards are fetched,
//   and nothing is said.
//   SEVERAL AT ONCE (the handoff's decision 18). A BURST is deliveries
//   announced within `burstMs` (10 s) of the one before; it ends that long
//   after the last. The first two that are said in a burst get their own
//   toasts; from the third, those named toasts are taken away and ONE toast
//   stands for the burst, "You have 3 new notes", whose "Open" leads to the
//   inbox; with each further one it is put up again with the new count, so
//   its 8 seconds start over. Every delivery is still announced by itself
//   (`admin--notes--live:delivery`), with `detail.burstMs`, the length of the
//   window, so that `admin--notes--alert` counts its once-per-burst chime by
//   the same clock. The burst is kept beside the controller (`burst`), like
//   `pending`: it outlives a Turbo visit.
// - `Notes::RecordChannel`, one per `record` target (an editor's drawer, the
//   media panel's notes, the mind graph's card): a thread of that record
//   changed, or went with a deleted block.
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
// viewer may not read): a signal sent from then on is received.
//
// NO PAGE REFRESH, NO MORPHING (decision D20): nothing here touches an editor
// form, the write queue or anything outside the notes parts.
const COALESCE_MS = 500
// What the person's stream has said and nobody has acted on yet: the
// deliveries to announce, and whether the count and the cards are due. Beside
// the controller, not on it (as `pool` is in `live/connection`): a signal
// waits half a second before anything is fetched, and a Turbo visit inside
// that window replaces <body> and the controller with it. The next page's
// controller takes these over (`connect`), so the toast is raised there.
//
// `person` is whose they are: the signed-in person's id as the page that was
// told gave it. A session that ended and was replaced by another sign-in in
// the same document must not inherit the ids of the person before (`connect`
// empties this for a different person). `live` is the controller of the
// <body> that is in the document now, the only one that may announce
// anything: a run of `inbox` that outlives its page hands what it has left
// to it (`handBack`).
const pending = { deliveries: new Set(), due: false, person: null }
let live = null

// The burst of deliveries being announced (see "SEVERAL AT ONCE"): when the
// last one was announced, how many of it were said in a toast, the named
// toasts that are its first two, and the one toast that replaced them. The
// elements may be gone (dismissed, timed out, left behind by a visit);
// removing one that is gone does nothing.
const NAMED_TOASTS = 2
const BURST_MS = 10000
const burst = { last: 0, said: 0, named: [], summary: null }

function endBurst() {
  Object.assign(burst, { last: 0, said: 0, named: [], summary: null })
}

export default class extends Controller {
  static targets = [ "record" ]
  static values = { unreadUrl: String, cardUrl: String, openThreadsUrl: String, deliveryUrl: String, person: String, burstMs: { type: Number, default: BURST_MS } }

  // Before the first target connects, which is before `connect`.
  initialize() {
    // How often Turbo has drawn each notes frame (`answered`).
    this.draws = new WeakMap()
    this.records = new Map()
    this.timers = new Map()
    this.stale = new WeakSet()
    this.dropped = false
  }

  connect() {
    this.element.dataset.notesTab = TAB
    this.person = listen({ channel: "Notes::PersonChannel" }, Object.assign((signal) => this.addressed(signal), {
      connected: () => this.online(),
      disconnected: () => this.offline(),
      rejected: () => this.sync()
    }))
    // A socket the server closed for good (the session ended; someone has
    // signed in again since) is opened again by the first page that asks.
    open()
    // What the page before this one was told and had not acted on -- its
    // timer not yet run, or its run still out when the visit came (that run
    // announces nothing more, `inbox`). Nothing of it for another person.
    if (pending.person !== this.personValue) {
      pending.deliveries.clear()
      pending.due = false
      pending.person = this.personValue
      endBurst()
    }
    // The tab's note drafts are this person's or nobody's (`forgetDrafts`).
    forgetDrafts(this.personValue)
    live = this
    if (pending.due || pending.deliveries.size > 0) this.soon("person", () => this.inbox())
    this.sync()
  }

  disconnect() {
    this.person?.()
    this.person = null
    this.records.forEach((record) => record.stop())
    this.records.clear()
    if (live === this) live = null
    // The timers go; what the person's stream said stays (`pending`).
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

  // `submit` on the sidebar's Sign out form: the tab's note drafts go with the
  // session. When the document actually goes (`pagehide`), not at the press:
  // with unsaved content the browser asks "Leave site?" first, and a person
  // who stays must find their half-typed note where it was. If they stay,
  // the next key or pointer press takes the intent back, so a later reload,
  // which is meant to keep drafts, removes nothing.
  signingOut() {
    const clear = () => forgetDrafts()
    const stay = () => window.removeEventListener("pagehide", clear)
    window.addEventListener("pagehide", clear, { once: true })
    document.addEventListener("pointerdown", stay, { once: true, capture: true })
    document.addEventListener("keydown", stay, { once: true, capture: true })
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

  // Whether every subscription of this page has been answered.
  sync() {
    const settled = Boolean(this.person?.up) && [ ...this.records.values() ].every((record) => record.stop.settled)
    this.element.dataset.notesLive = settled ? "connected" : "connecting"
  }

  // The person's stream is up. After a drop, what the person's signals lead
  // to is fetched once; each record's own subscription does the same for
  // its part (`recordTargetConnected`).
  online() {
    if (this.dropped) this.soon("person", () => this.inbox())
    this.dropped = false
    this.sync()
  }

  offline() {
    this.dropped = true
    this.sync()
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
    const counts = await this.json(url)
    if (counts && element.isConnected) this.notes?.refreshCounts(counts)
  }

  // `admin--notes--drawer`, on the same element.
  get notes() {
    return this.application.getControllerForElementAndIdentifier(this.element, "admin--notes--drawer")
  }

  // --- the person's inbox -----------------------------------------------------------

  // A signal on the person's stream. Every delivery named in a burst is
  // announced; the count and the cards are fetched once for all of them.
  addressed(signal) {
    if (signal?.kind === "delivery") {
      if (Number.isInteger(signal.delivery_id)) pending.deliveries.add(signal.delivery_id)
    } else if (signal?.kind !== "inbox" || signal.origin === TAB) {
      return
    }
    pending.due = true
    this.soon("person", () => this.inbox())
  }

  // ONLY THE CONTROLLER OF THE PAGE IN THE DOCUMENT ANNOUNCES. A run can
  // outlive its page: a Turbo visit replaces <body> while the count or a
  // delivery is being fetched. After every `await` the run asks whether it
  // is still `live`; if not it announces nothing -- its `record` targets are
  // the old page's, so it would judge "is the person looking at this
  // thread" by a page that is gone -- puts back the delivery it was reading
  // and hands everything to the page that is there (`handBack`). An id is
  // taken off `pending` before it is read, so two runs never read the same
  // one, and it is put back only by the run that took it: no delivery is
  // announced twice, and none is stranded waiting for another signal.
  async inbox() {
    pending.due = false
    await this.refreshInbox()
    if (live !== this) return this.handBack()

    for (const id of [ ...pending.deliveries ]) {
      // Taken by another run since this one began.
      if (!pending.deliveries.delete(id)) continue
      const row = await this.read(id)
      if (live !== this) return this.handBack(id)
      if (row) this.announce(row)
    }
  }

  // This run's page is gone. What it had not announced is the next page's:
  // the delivery it was reading goes back, the count and the cards are due
  // again (the answer went to the old page's elements), and the controller
  // that is live runs -- now, not at the next signal. Without one yet, its
  // `connect` will. Nothing is handed to another person's page.
  handBack(id = null) {
    if (pending.person !== this.personValue) return
    if (id != null) pending.deliveries.add(id)
    pending.due = true
    live?.soon("person", () => live?.inbox())
  }

  // One delivery, read through the scoped endpoint before anything is said.
  // Not found or refused (the record left the viewer's scope, or went to the
  // trash): null, and nothing is said.
  read(id) {
    // The address of delivery 0, with this one's id as its last segment.
    const url = new URL(this.deliveryUrlValue, window.location.origin)
    url.pathname = url.pathname.replace(/\/0$/, `/${encodeURIComponent(id)}`)
    return this.json(url.pathname + url.search)
  }

  // In one task, with no `await`: the controller that was live when the
  // delivery had been read is the one that judges and says it.
  announce(row) {
    const now = Date.now()
    if (now - burst.last > this.burstWindow) endBurst()
    burst.last = now

    const shown = this.watching(row.thread_id)
    const detail = { id: row.id, reason: row.reason, sentence: row.sentence, title: row.title, excerpt: row.excerpt, url: row.url, threadId: row.thread_id, shown, burstMs: this.burstWindow }
    document.dispatchEvent(new CustomEvent("admin--notes--live:delivery", { detail }))
    if (shown) return

    // The first two of a burst by name; from the third, one toast for all.
    burst.said += 1
    if (burst.said <= NAMED_TOASTS) {
      const toast = this.toast(row)
      if (toast) burst.named.push(toast)
    } else {
      this.summarise()
    }
  }

  // The length of a burst's window: `burstMs`, or the 10 seconds for
  // anything that is not a positive finite number -- a NaN here would make a
  // burst that never ends.
  get burstWindow() {
    const ms = this.burstMsValue
    return Number.isFinite(ms) && ms > 0 ? ms : BURST_MS
  }

  // "You have 3 new notes": in the place of the burst's named toasts, and of
  // itself when the count grows -- a new element, so its 8 seconds start
  // again (`admin--ui--toast` counts from when it connects). "Open" is the
  // template's own, which leads to the inbox.
  summarise() {
    burst.named.forEach((toast) => toast.remove())
    burst.named = []
    burst.summary?.remove()

    const toast = this.blankToast()
    if (!toast) return
    toast.dataset.noteToast = "many"
    toast.querySelector("span:not([aria-hidden])").textContent = messages(this.element).t("notes.script.toast.many", { count: burst.said })
    document.getElementById("toasts").append(toast)
    burst.summary = toast
  }

  // Whether the person is looking at that thread, THE ONE PREDICATE: it is
  // the view of a notes frame that is open here, in a document that is not
  // hidden. It is `detail.shown` of the delivery's event, what keeps the
  // toast away, and -- its second half, in `fetchPart` -- what lets a thread
  // be fetched at all. The window's focus is not part of it.
  watching(threadId) {
    if (document.hidden) return false
    return this.recordTargets.some((element) => {
      const view = element.hidden ? null : element.querySelector("turbo-frame#notes > [data-notes-view='thread']")
      return Boolean(view) && view.dataset.noteThread === String(threadId) && !view.querySelector("[data-note-gone]")
    })
  }

  async refreshInbox() {
    const count = await this.json(this.unreadUrlValue)
    const badge = document.getElementById("sidebar-badge-dashboard")
    if (count && badge) {
      const unread = Number(count.unread) || 0
      badge.textContent = unread > 0 ? String(unread) : ""
      badge.hidden = unread === 0
      badge.toggleAttribute("data-badge", unread > 0)
    }
    this.reload(document.getElementById("notes-for-you"), this.cardUrlValue)
    this.reload(document.getElementById("notes-open-threads"), this.openThreadsUrlValue)
  }

  // The dashboard's two cards are frames drawn with the page, with no `src`
  // of their own: the first signal gives them one, later ones reload it.
  reload(frame, url) {
    if (!frame || !url) return
    if (frame.getAttribute("src") === url) frame.reload()
    else frame.src = url
  }

  // JSON from one of CS Studio's own endpoints, or null: a refusal, a
  // redirect to the sign-in page (which answers 200 with a page) and
  // anything else that is not JSON are all "nothing to show".
  async json(url) {
    const response = await fetch(url, { headers: { Accept: "application/json" } })
    if (!response.ok || response.redirected || !(response.headers.get("Content-Type") || "").includes("json")) return null
    return response.json()
  }

  // The layout's `#toast-note-template` with an accent dot before its
  // sentence (accent means "for you"), not yet in the page; nothing where
  // there is no template or no region to put it in.
  blankToast() {
    const toast = document.getElementById("toast-note-template")?.content.firstElementChild?.cloneNode(true)
    if (!toast || !document.getElementById("toasts")) return null

    const dot = document.createElement("span")
    dot.className = "size-1.5 shrink-0 rounded-full bg-accent"
    dot.setAttribute("aria-hidden", "true")
    toast.prepend(dot)
    return toast
  }

  // One delivery's toast: "Dana mentioned you on Pricing" and "Open". The
  // action is a GET form, whose query a browser rebuilds from its fields:
  // the URL's parameters go in as hidden fields. Answers the element.
  toast(row) {
    const toast = this.blankToast()
    const region = document.getElementById("toasts")
    if (!toast) return null

    toast.dataset.noteToast = "one"
    toast.querySelector("span:not([aria-hidden])").textContent = messages(this.element).t("notes.script.toast.on", { sentence: row.sentence, title: row.title })

    const form = toast.querySelector("form")
    const target = new URL(row.url, window.location.origin)
    form.action = target.pathname
    target.searchParams.forEach((value, name) => {
      const field = document.createElement("input")
      field.type = "hidden"
      field.name = name
      field.value = value
      form.append(field)
    })
    region.append(toast)
    return toast
  }
}
