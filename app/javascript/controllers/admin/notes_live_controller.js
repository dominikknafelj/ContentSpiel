import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { messages } from "i18n/messages"
import { forgetDrafts } from "controllers/admin/note_composer_controller"

// Live delivery of notes (notes spec §6). Lives on <body>. A signal over the
// cable says only THAT something changed (`Notes::Signals`: a kind and ids);
// this controller then fetches the part again through the same scoped GET the
// page used on load, so what a tab can show is always what its viewer may
// read. The consumer is the one bundled in turbo-rails; nothing but this file
// asks for it, so a public page opens no socket, and the socket is closed
// again when a Turbo visit leaves CS Studio (`listen`).
//
// TWO SUBSCRIPTIONS.
// - `Notes::PersonChannel`, once per tab. `delivery`: a delivery was written
//   for the viewer. The sidebar's count and, on the dashboard, the two cards
//   are fetched again; then that one delivery is FETCHED as data -- the
//   signal may have reached someone who has since lost the right to read the
//   record, and a refusal ends it there, with nothing said -- announced on
//   `document` (`admin--notes-live:delivery`) and raised as a toast. No toast
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
//   (`admin--notes-live:delivery`), with `detail.burstMs`, the length of the
//   window, so that `admin--notes-alert` counts its once-per-burst chime by
//   the same clock. The burst is kept beside the controller (`burst`), like
//   `pending`: it outlives a Turbo visit.
// - `Notes::RecordChannel`, one per `record` target (an editor's drawer, the
//   media panel's notes, the mind graph's card): a thread of that record
//   changed, or went with a deleted block.
//
// REFRESHING WITHOUT LOSING WORK (§6.3). What is READ is replaced; what is
// TYPED is never touched.
// - The list view: everything in `#notes-list` is replaced AROUND a new-note
//   field that is on screen. The field is not moved, not even within the
//   list, so its text, its names, its open picker and the focus stay.
// - The thread view: its `messages` part is replaced -- Back, the heading,
//   Notify, Close and Pin are in it, and show a state someone else can
//   change. A message with an open edit form or an open "Delete this note?"
//   stays the element it is. The `reply` part is never replaced: only its
//   Resolve / Reopen button and the empty form that button sends are swapped
//   when the thread's state changed, so the button says what it now does.
//   A message's reaction chips are read, not typed: they are redrawn with
//   their message, and in a message that stays the element it is (a delete
//   question is open) the chips alone are swapped. The set of emoji someone
//   has open under a message ("Add a reaction") is open afterwards too.
//   A message's files are the very elements that were there (a picture is
//   not fetched again, a GIF that plays goes on playing).
//   Whatever had the focus has it afterwards (the same element, or the same
//   control of the new markup), and the scroll position stays -- unless the
//   reader was at the bottom, who stays at the bottom. Messages that arrived
//   are set off by a "NEW" divider above the first of them, which stays
//   where it first stood until the thread is left; a reader who is not at
//   the bottom gets "1 new message ↓" above the reply field and nothing
//   moves.
// - A composer is never replaced by a refresh, and that goes for one that
//   holds CHOSEN FILES and no text as for one that holds text: the thread's
//   reply part and the list's new-note field are left where they are (a
//   file field's files cannot be put back by a script).
// - A thread that is gone (its GET answers the list, "This note is gone")
//   while its reply field or an edit holds text, or its reply field holds
//   chosen files: the text stays, with "This
//   thread was deleted" above the field, and everything that would send it
//   to a thread that is not there is switched off. Without typed text the
//   frame goes to the list.
// - A drawer that is closed gets its counts only (`data-notes-counts-url`,
//   handed to `admin--notes#refreshCounts`): fetching a thread is what marks
//   it read, and nobody is reading a closed drawer. It is remembered as
//   stale and fetched when it is opened again. The same goes for a THREAD
//   in a document that is hidden (another tab is in front, the window is
//   minimised): its GET would read the note on the person's behalf, so it
//   gets the counts, the toast is raised, the delivery stays unread, and the
//   thread is fetched when the document is visible again (`visible`). A
//   list is fetched hidden or not: reading a list reads nothing. A part that
//   draws itself (the graph's card) hears `admin--notes-live:changed` on its
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
// received. A session that ended has its socket closed by the server
// (`Session#disconnect_cable`); the consumer's one reconnect is refused with
// `reconnect: false`, and it stops there, silently.
// `data-notes-live="connected"` on <body> says that every subscription of
// this page has been answered (confirmed, or rejected for a record the
// viewer may not read): a signal sent from then on is received.
//
// NO PAGE REFRESH, NO MORPHING (decision D20): nothing here touches an editor
// form, the write queue or anything outside the notes parts.
const COALESCE_MS = 500
const NEAR_BOTTOM = 48
const FOCUSABLE = "a[href], button:not([disabled]), input:not([type=hidden]):not([disabled]), textarea:not([disabled]), select:not([disabled]), summary, [tabindex]"

// This tab, for as long as its document lives: the shape the server echoes
// (`Notes::Signals::TAB`, lower-case letters, digits and dashes, 8 to 40).
const TAB = `tab-${Array.from(crypto.getRandomValues(new Uint8Array(16)), (byte) => byte.toString(16).padStart(2, "0")).join("")}`

// The subscriptions of this document, one per channel-and-parameters, shared
// by whoever listens. A Turbo visit replaces <body>, and with it this
// controller and its `record` targets: the old ones let go and the new ones
// ask in the same task. Unsubscribing and subscribing again to the same
// identifier at once is what Action Cable can't promise the order of (the
// server works its commands on a pool; a late "unsubscribe" would remove the
// new subscription, and the confirmation of the old one would have been taken
// for it), so a subscription nobody listens to is let go a task later, and
// one asked for again in between is simply kept. When the last one goes, the
// tab has left CS Studio and the socket is closed.
const pool = new Map()

function listen(params, listener) {
  const key = JSON.stringify(params)
  let entry = pool.get(key)
  if (!entry) {
    entry = { listeners: new Set(), up: false, settled: false, rejected: false }
    const tell = (name, ...args) => [ ...entry.listeners ].forEach((each) => each[name]?.(...args))
    entry.subscription = cable.subscribeTo(params, {
      connected: () => { entry.up = entry.settled = true; tell("connected") },
      disconnected: () => { entry.up = entry.settled = false; tell("disconnected") },
      rejected: () => { entry.rejected = entry.settled = true; tell("rejected") },
      received: (signal) => tell("received", signal)
    })
    pool.set(key, entry)
  }
  clearTimeout(entry.release)
  entry.listeners.add(listener)

  const stop = () => {
    entry.listeners.delete(listener)
    if (entry.listeners.size > 0) return
    entry.release = setTimeout(async () => {
      const subscription = await entry.subscription
      if (entry.listeners.size > 0) return
      pool.delete(key)
      // A rejected one is forgotten on both sides already.
      if (!entry.rejected) subscription.unsubscribe()
      if (pool.size === 0) (await cable.getConsumer()).disconnect()
    }, 0)
  }
  return { entry, stop }
}

// What the person's stream has said and nobody has acted on yet: the
// deliveries to announce, and whether the count and the cards are due. Beside
// `pool`, not on the controller: a signal waits half a second before anything
// is fetched, and a Turbo visit inside that window replaces <body> and the
// controller with it. The next page's controller takes these over
// (`connect`), so the toast is raised there.
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

// The last segment of the address a control's form posts to: "follow", "pin".
const change = (control) => control.closest("form")?.getAttribute("action")?.split("?")[0].split("/").pop()

// The controls of a thread's first rows, each as a name and how to find it
// in markup drawn again. Notify and Pin are a form each; which of the two
// words the form's address ends in changes with the thread.
const CONTROLS = [
  [ "back", (root) => root.querySelector("a[data-note-back]") ],
  [ "close", (root) => root.querySelector("button[data-note-close]") ],
  [ "leave", (root) => root.querySelector("button[data-note-leave]") ],
  [ "notify", (root) => [ ...root.querySelectorAll("[data-note-actions] form button") ].find((button) => [ "follow", "unfollow" ].includes(change(button))) ],
  [ "pin", (root) => [ ...root.querySelectorAll("[data-note-actions] form button") ].find((button) => [ "pin", "unpin" ].includes(change(button))) ],
  [ "state", (root) => root.querySelector("button[data-note-state]") ]
]

const nearBottom = (scroller) => scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < NEAR_BOTTOM

export default class extends Controller {
  static targets = [ "record" ]
  static values = { unreadUrl: String, cardUrl: String, openThreadsUrl: String, deliveryUrl: String, person: String, burstMs: { type: Number, default: BURST_MS } }

  // Before the first target connects, which is before `connect`.
  initialize() {
    this.records = new Map()
    this.timers = new Map()
    this.stale = new WeakSet()
    this.dropped = false
  }

  connect() {
    this.element.dataset.notesTab = TAB
    this.person = listen({ channel: "Notes::PersonChannel" }, {
      connected: () => this.online(),
      disconnected: () => this.offline(),
      rejected: () => this.sync(),
      received: (signal) => this.addressed(signal)
    })
    // A socket the server closed for good (the session ended; someone has
    // signed in again since) is opened again by the first page that asks.
    cable.getConsumer().then((consumer) => consumer.ensureActiveConnection())
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
    this.person?.stop()
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
    const { entry, stop } = listen({ channel: "Notes::RecordChannel", type: element.dataset.notesType, id: String(element.dataset.notesId) }, {
      connected: () => {
        if (record.dropped) this.soon(element, () => this.refresh(element, null))
        record.dropped = false
        this.sync()
      },
      disconnected: () => {
        record.dropped = true
        this.sync()
      },
      rejected: () => this.sync(),
      received: (signal) => {
        if (signal?.kind !== "threads" || signal.origin === TAB) return
        this.soon(element, () => this.refresh(element, signal.thread_id ?? null))
      }
    })
    this.records.set(element, Object.assign(record, { entry, stop }))
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
    this.sent = { frame, form: event.target, held: view ? this.hold(view) : null }
  }

  // `turbo:before-frame-render` on the document: see "THE ANSWER TO ONE OF
  // THIS TAB'S OWN BUTTONS" above.
  answered(event) {
    const frame = event.target
    if (frame.id !== "notes") return
    const sent = this.sent
    this.sent = null
    if (!sent || sent.frame !== frame) return

    const view = frame.querySelector(":scope > [data-notes-view='thread']")
    const answer = event.detail.newFrame.querySelector(":scope > [data-notes-view='thread']")
    if (!view || !answer || answer.dataset.noteThread !== view.dataset.noteThread || view.querySelector("[data-note-gone]")) return
    if (!view.querySelector(":scope > [data-note-part='messages']") || !view.querySelector(":scope > [data-note-part='reply']")) return
    // The form of a message being worked in: that message is what the answer redraws.
    if (sent.form.closest("[data-note-message]")?.querySelector("form[data-note-composer], [data-note-delete-question]")) return

    const reply = sent.form.matches("[data-note-part='reply'] form[data-note-composer]")
    event.detail.render = () => this.redrawThread(frame, view, answer, null, { own: true, reply, held: sent.held })
  }

  // `admin--notes:opened`: a drawer that was closed while its record changed
  // is fetched now. A task later, when `admin--notes#show` has either left
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
    const settled = Boolean(this.person?.entry.up) && [ ...this.records.values() ].every((record) => record.entry.settled)
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
    element.dispatchEvent(new CustomEvent("admin--notes-live:changed", { detail: { threadId } }))

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

    const response = await fetch(this.address(frame, view), { headers: { Accept: "text/html", "Turbo-Frame": "notes" } })
    // Signed out, the record out of reach: nothing to draw, and nothing said.
    const answer = response.ok ? new DOMParser().parseFromString(await response.text(), "text/html").querySelector("turbo-frame#notes > [data-notes-view]") : null
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
    } else {
      const subject = view.querySelector(":scope > #notes-new input[name='subject']")?.value
      if (subject && !url.searchParams.has("compose")) url.searchParams.set("compose", subject)
    }
    return url.pathname + url.search
  }

  redrawList(view, answer) {
    if (answer.dataset.notesView !== "list") return
    const next = document.importNode(answer, true)
    const field = view.querySelector(":scope > #notes-new")
    const held = this.hold(view)
    const scroller = this.scroller(view)
    const top = scroller.scrollTop
    const resolved = view.querySelector("#notes-resolved-section")?.open

    if (field) {
      // Around the field, which stays where it is: what the answer has
      // before the field's place goes before it, the rest after. In an
      // answer without the place (the block the note is on went a moment
      // ago) the counts and the list's sentence go before it.
      const place = next.querySelector(":scope > #notes-new")
      const parts = [ ...next.children ]
      const at = place ? parts.indexOf(place) : parts.findIndex((part) => !part.matches("[hidden], [role='status']"))
      // Not the field's own place, and no second "New note" beside the field.
      const drawn = (part) => part !== place && !part.querySelector("[data-note-new-link]")
      ;[ ...view.children ].forEach((part) => { if (part !== field) part.remove() })
      field.before(...(at < 0 ? parts : parts.slice(0, at)).filter(drawn))
      field.after(...(at < 0 ? [] : parts.slice(at)).filter(drawn))
    } else {
      view.replaceChildren(...next.children)
    }

    const section = view.querySelector("#notes-resolved-section")
    if (resolved && section) section.open = true
    scroller.scrollTop = top
    this.give(view, held)
  }

  // `own`: the answer to this tab's own button (`answered`), not a signal's
  // fetch -- nothing in it "arrived". `reply`: the reply's composer is what
  // was sent, so its part is the answer's. `held`: what had the focus when
  // the button was pressed (`asked`).
  redrawThread(frame, view, answer, url, { own = false, reply: sentReply = false, held: heldBefore = null } = {}) {
    const old = view.querySelector(":scope > [data-note-part='messages']")
    const reply = view.querySelector(":scope > [data-note-part='reply']")
    if (!old || !reply) return
    // A message someone is working in: an open edit form, an open question.
    const busy = [ ...old.querySelectorAll("[data-note-message]") ].filter((message) => message.querySelector("form[data-note-composer], [data-note-delete-question]"))

    if (answer.dataset.notesView !== "thread" || answer.dataset.noteThread !== view.dataset.noteThread) return this.gone(frame, view, old, reply, busy, answer, url)
    if (view.querySelector("[data-note-gone]")) return

    const scroller = this.scroller(view)
    const atBottom = nearBottom(scroller)
    const top = scroller.scrollTop
    // What had the focus at the press -- unless the person has since moved
    // into a field: then that field, which is where their typing goes. (It
    // is noted, not left alone: a message that is kept is moved into the new
    // part, and an element that is moved drops the focus.)
    const held = (!this.typing(view) && heldBefore) || this.hold(view)
    const known = new Set([ ...old.querySelectorAll("[data-note-message]") ].map((message) => message.dataset.noteMessage))
    const next = document.importNode(answer.querySelector(":scope > [data-note-part='messages']"), true)
    const find = (id) => [ ...next.querySelectorAll("[data-note-message]") ].find((message) => message.dataset.noteMessage === id)

    const arrived = [ ...next.querySelectorAll("[data-note-message]") ].filter((message) => !known.has(message.dataset.noteMessage))
    // The set of emoji that is open under a message, to be open again.
    // (Not after this tab's own press: an emoji was picked from it.)
    const picking = own ? null : old.querySelector("details[data-reaction-add][open]")?.closest("[data-note-message]")?.dataset.noteMessage
    // The very elements, in the place the answer gives their messages -- shown,
    // should that place now be among the folded ones; one whose message was
    // deleted meanwhile keeps its text at the end.
    busy.forEach((message) => {
      const twin = find(message.dataset.noteMessage)
      // Its reactions are what others did, not what is being typed: the new
      // ones, disabled under an edit form (which is not touched). Not while
      // its own set of emoji is open.
      if (twin && !message.querySelector("details[data-reaction-add][open]")) this.takeReactions(message, twin, { disabled: Boolean(message.querySelector("form[data-note-composer]")) })
      if (twin) twin.replaceWith(message)
      else next.append(message)
      message.closest("details")?.setAttribute("open", "")
    })
    // A message's files never change (they are fixed when it is written), so
    // the very elements are kept in the place the answer gives them: a
    // picture is not fetched again for every refresh (its address is never
    // cached, `Admin::NoteFilesController`), and a GIF someone set playing
    // goes on playing. A message being worked in was moved whole, above.
    old.querySelectorAll("[data-note-message]").forEach((message) => {
      if (busy.includes(message)) return
      const kept = message.querySelector(":scope > [data-note-files]")
      const place = kept && find(message.dataset.noteMessage)?.querySelector(":scope > [data-note-files]")
      if (place) place.replaceWith(kept)
    })
    if (old.querySelector("details[data-note-fold]")?.open) next.querySelector("details[data-note-fold]")?.setAttribute("open", "")
    if (picking) find(picking)?.querySelector("details[data-reaction-add]")?.setAttribute("open", "")
    // The divider stays where it first stood while the thread is open.
    const first = old.querySelector("[data-note-new-divider]")?.nextElementSibling?.dataset.noteMessage
    const mark = own ? null : (first && find(first)) || arrived[0]
    if (mark) {
      mark.closest("details")?.setAttribute("open", "")
      mark.before(this.divider())
    }

    old.replaceWith(next)
    view.dataset.state = answer.dataset.state
    this.takeCounts(view, answer)
    this.settle(reply, answer)
    const nextReply = sentReply && document.importNode(answer.querySelector(":scope > [data-note-part='reply']"), true)
    // The reply was sent from its part -- the field, or the button beside
    // it: the focus goes to the field of the part that takes its place.
    const fromReply = Boolean(nextReply && held?.element && reply.contains(held.element))
    if (nextReply) reply.replaceWith(nextReply)
    if (fromReply) nextReply.querySelector("textarea")?.focus({ preventScroll: true })
    else this.give(view, held)

    // The reader at the bottom stays there, and so sees what arrived; anyone
    // else stays where they are and is told.
    scroller.scrollTop = atBottom ? scroller.scrollHeight : top
    if (nextReply) return
    if (atBottom) reply.querySelector(":scope > [data-note-jump]")?.remove()
    else if (arrived.length > 0 && !own) this.jump(view, reply, scroller, arrived.length)
  }

  // The thread is no longer there: its GET answered the list. With nothing
  // typed, the frame goes where that answer came from (the list, which says
  // "This note is gone"). With text in the reply field or in an edit, the
  // text stays (spec §6.3): the messages go, Back and Close stay, Notify, Pin
  // and every way of sending are taken away -- each would be answered with
  // the list, over the text -- and the field says why.
  gone(frame, view, old, reply, busy, answer, url) {
    const counts = answer.querySelector("[data-admin--notes-target~='counts']")?.dataset.counts
    if (counts) this.notes?.refreshCounts(JSON.parse(counts))
    if (view.querySelector("[data-note-gone]")) return

    const editing = busy.filter((message) => [ ...message.querySelectorAll("textarea") ].some((field) => field.value !== field.defaultValue))
    // Chosen files are typed work too: a field that holds some is kept, even
    // with no text beside them.
    const files = reply.querySelector("input[type='file']")?.files.length > 0
    if (!reply.querySelector("textarea")?.value && !files && editing.length === 0) {
      const list = new URL(url, window.location.origin)
      frame.src = list.pathname + list.search
      return
    }

    const held = this.hold(view)
    const rows = old.firstElementChild
    ;[ ...old.children ].forEach((part) => { if (part !== rows) part.remove() })
    rows?.querySelectorAll("[data-note-actions] form").forEach((form) => form.remove())
    old.append(...editing)

    const line = document.createElement("p")
    line.dataset.noteGone = ""
    line.setAttribute("role", "status")
    line.className = "rounded-cs border border-line bg-sunken px-3 py-2 text-[13px] text-ink"
    line.textContent = messages(this.element).t("notes.script.live.gone")
    ;(reply.querySelector("form[data-note-composer]") || reply.lastElementChild).before(line)
    reply.querySelector(":scope > [data-note-jump]")?.remove()

    view.querySelectorAll("form").forEach((form) => form.addEventListener("submit", (event) => event.preventDefault()))
    view.querySelectorAll("button[type='submit']").forEach((button) => {
      // No longer the composer's to enable when the field has text.
      button.removeAttribute("data-admin--note-composer-target")
      button.disabled = true
    })
    this.give(view, held)
  }

  // Resolve or Reopen, in the composer's bottom row, and the empty form it
  // sends: swapped when the thread's state changed, and only then. Nothing
  // else of the reply part is ever replaced.
  settle(reply, answer) {
    const button = reply.querySelector("button[data-note-state]")
    const twin = answer.querySelector("[data-note-part='reply'] button[data-note-state]")
    if (!button || !twin || button.dataset.noteState === twin.dataset.noteState) return

    const form = button.form
    const formTwin = answer.querySelector(`[data-note-part='reply'] form[id="${CSS.escape(twin.getAttribute("form"))}"]`)
    if (form && formTwin) form.replaceWith(document.importNode(formTwin, true))
    button.replaceWith(document.importNode(twin, true))
  }

  // The "NEW" divider (handoff): an accent line filling the row, then the
  // word.
  divider() {
    const divider = document.createElement("div")
    divider.dataset.noteNewDivider = ""
    divider.className = "flex items-center gap-2 px-4 pt-2.5"
    const line = document.createElement("span")
    line.className = "h-px flex-1 bg-accent"
    const label = document.createElement("span")
    label.className = "font-cs-mono text-[10px] uppercase tracking-mono text-accent"
    label.textContent = messages(this.element).t("notes.script.live.new_divider")
    divider.append(line, label)
    return divider
  }

  // "1 new message ↓", 12px above the reply field (the dock is `sticky`, so
  // the button stands on it wherever the thread is scrolled to; 13px from the
  // dock's padding edge, which is 12px above the line on its top). It counts
  // what arrived since the reader was last at the bottom, and goes when they
  // are there again -- by pressing it or by scrolling.
  jump(view, reply, scroller, count) {
    let button = reply.querySelector(":scope > [data-note-jump]")
    const total = count + Number(button?.dataset.count || 0)
    if (!button) {
      button = document.createElement("button")
      button.type = "button"
      button.dataset.noteJump = ""
      button.className = "absolute bottom-full left-1/2 mb-[13px] -translate-x-1/2 cursor-pointer whitespace-nowrap rounded-cs border border-line-strong bg-surface px-2.5 py-[5px] text-[12px] font-medium text-ink shadow-menu focus-visible:outline-2 focus-visible:outline-accent"
      // The page scrolls where there is no drawer; its scroll is the window's.
      const source = scroller === document.scrollingElement ? window : scroller
      const watch = () => { if (!button.isConnected || nearBottom(scroller)) dismiss() }
      const dismiss = () => {
        source.removeEventListener("scroll", watch)
        if (button.contains(document.activeElement)) view.focus({ preventScroll: true })
        button.remove()
      }
      source.addEventListener("scroll", watch, { passive: true })
      button.addEventListener("click", () => {
        if (button.contains(document.activeElement)) view.focus({ preventScroll: true })
        scroller.scrollTop = scroller.scrollHeight
        dismiss()
      })
      reply.prepend(button)
    }
    button.dataset.count = String(total)
    button.textContent = messages(this.element).t("notes.script.live.new_messages", { count: total })
  }

  // The answer's own copy of the record's counts, in the place of the one
  // the view had: `admin--notes` reads a counts element as it connects.
  takeCounts(view, answer) {
    const counts = answer.querySelector(":scope > [data-admin--notes-target~='counts']")
    const own = view.querySelector(":scope > [data-admin--notes-target~='counts']")
    if (counts && own) own.replaceWith(document.importNode(counts, true))
  }

  async refreshCounts(element) {
    const url = element.dataset.notesCountsUrl
    if (!url) return
    const counts = await this.json(url)
    if (counts && element.isConnected) this.notes?.refreshCounts(counts)
  }

  scroller(view) {
    return view.closest("[data-notes-scroller]") || document.scrollingElement
  }

  // What has the focus inside `root`, to be given back after a redraw
  // (`give`): the element itself, which may survive; failing that, what it
  // was -- one of a thread's own controls, an element with an id (a row of
  // the list), or the nth control of a message.
  hold(root) {
    const active = document.activeElement
    if (!active || active === document.body || !root.contains(active)) return null

    const message = active.closest("[data-note-message]")
    return {
      element: active,
      control: CONTROLS.find(([ , find ]) => find(root) === active)?.[0],
      id: active.id || null,
      message: message && root.contains(message) ? message.dataset.noteMessage : null,
      index: message ? [ ...message.querySelectorAll(FOCUSABLE) ].indexOf(active) : -1,
      // A reaction's chip, or an emoji of the set: by its emoji, since the
      // chips before it may be others after the redraw.
      reaction: active.closest("[data-note-reactions], [data-reaction-add]") ? active.dataset.reaction || active.value || null : null,
      selection: typeof active.selectionStart === "number" ? [ active.selectionStart, active.selectionEnd, active.selectionDirection ] : null
    }
  }

  // Never left to fall to <body>: when nothing of the new markup is what had
  // the focus, the view takes it (or, for the list, what holds it: the
  // drawer).
  give(root, held) {
    if (!held || document.activeElement === held.element) return

    const message = held.message ? [ ...root.querySelectorAll("[data-note-message]") ].find((each) => each.dataset.noteMessage === held.message) : null
    const target = (held.element.isConnected && held.element)
      || (held.control && CONTROLS.find(([ name ]) => name === held.control)[1](root))
      || (held.id && [ ...root.querySelectorAll("[id]") ].find((each) => each.id === held.id))
      || (message && held.reaction && this.reaction(message, held.reaction))
      || (message && [ ...message.querySelectorAll(FOCUSABLE) ][held.index])
      || root.closest("[tabindex]")
    if (!target) return

    target.focus({ preventScroll: true })
    if (target === held.element && held.selection) target.setSelectionRange(...held.selection)
  }

  // Whether the focus is in a field of the view right now.
  typing(root) {
    const active = document.activeElement
    return Boolean(active?.isConnected && root.contains(active) && active.matches("textarea, input:not([type=hidden]), select"))
  }

  // The chip of an emoji in a message as it is drawn now; the way to the set
  // (the add chip, or the meta line's control once the row is gone) when that
  // emoji's last reaction went and its chip with it. Compared as data, never
  // built into a selector: the emoji is whatever the button held.
  reaction(message, emoji) {
    return [ ...message.querySelectorAll("[data-note-reactions] button[data-reaction]:not([disabled])") ].find((chip) => chip.dataset.reaction === emoji)
      || message.querySelector("details[data-reaction-add] > summary")
  }

  // A message that stays the element it is gets the answer's reactions: its
  // row of chips, or -- for a message nobody has reacted to -- the control in
  // its meta line. Either may have come or gone since, so each is taken out
  // and put where the message's own markup has it: the row before whatever
  // is asked under the text, the control before the "⋯" menu.
  //
  // `disabled`: the message is being edited. The answer draws it as it is
  // for everyone else, with chips to press; here they are made what
  // `ReactionsComponent` draws under an edit form -- its `:disabled` state:
  // the row at half opacity taking no pointer, every button `disabled`, the
  // add chip a disabled button in place of the <details>, and no control in
  // the meta line.
  takeReactions(message, twin, { disabled = false } = {}) {
    const row = twin.querySelector(":scope > [data-note-reactions]")
    const control = disabled ? null : twin.querySelector(":scope > div > details[data-reaction-add]")
    if (row && disabled) {
      row.dataset.noteReactions = "disabled"
      row.classList.add("pointer-events-none", "opacity-50")
      row.querySelectorAll("details[data-reaction-add]").forEach((add) => {
        const summary = add.querySelector("summary")
        const button = document.createElement("button")
        button.type = "button"
        button.className = summary.className
        button.setAttribute("aria-label", summary.getAttribute("aria-label"))
        button.dataset.reactionAdd = "true"
        button.append(...summary.childNodes)
        add.replaceWith(button)
      })
      row.querySelectorAll("button").forEach((button) => { button.disabled = true })
    }
    message.querySelectorAll(":scope > [data-note-reactions], :scope > div > details[data-reaction-add]").forEach((old) => old.remove())
    if (row) {
      const under = message.querySelector(":scope > [role='alert'], :scope > [data-note-delete-question]")
      if (under) under.before(row)
      else message.append(row)
    }
    if (control) {
      const menu = message.querySelector(":scope > div > [data-controller~='admin--menu']")
      if (menu) menu.before(control)
      else message.firstElementChild?.append(control)
    }
  }

  // `admin--notes`, on the same element.
  get notes() {
    return this.application.getControllerForElementAndIdentifier(this.element, "admin--notes")
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
    document.dispatchEvent(new CustomEvent("admin--notes-live:delivery", { detail }))
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
  // again (`admin--toast` counts from when it connects). "Open" is the
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
