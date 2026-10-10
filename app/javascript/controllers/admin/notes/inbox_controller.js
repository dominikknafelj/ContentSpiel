import { Controller } from "@hotwired/stimulus"
import { messages } from "i18n/messages"
import { TAB, listen, open } from "live/connection"
import { json } from "notes/json"
import { report } from "live/state"
import { forgetDrafts } from "controllers/admin/notes/composer_controller"

// The person's side of live notes (notes spec §6): the sidebar's count, the
// dashboard's two cards, the toasts and their bursts. Lives on <body>, so
// every screen of CS Studio has the person's stream. A signal over the cable
// says only THAT something changed (`Notes::Signals`: a kind and ids); this
// controller then fetches what it shows through the scoped endpoints, so
// what a tab says is always what its viewer may read. The record's side --
// a thread or a list kept current while someone reads or types in it -- is
// `admin--notes--live`; the connection both listen through is
// `live/connection`; the chime and the desktop notification are
// `admin--notes--alert`, which hears this controller's announcement.
//
// ONE SUBSCRIPTION.
// `Notes::PersonChannel`, once per tab. `delivery`: a delivery was written
// for the viewer. The sidebar's count and, on the dashboard, the two cards
// are fetched again; then that one delivery is FETCHED as data -- the
// signal may have reached someone who has since lost the right to read the
// record, and a refusal ends it there, with nothing said -- announced on
// `document` (`admin--notes--inbox:delivery`) and raised as a toast. No toast
// when the person is LOOKING AT that thread (`watching`, the one predicate,
// which `admin--notes--live` answers: it is the view of a notes frame of
// this tab, and the document is not hidden -- the window's focus is not
// asked for, so two windows side by side both stay live): the thread's own
// refresh shows the message and,
// being the thread's GET, reads the delivery. `inbox`: deliveries of theirs
// were read or removed elsewhere; only the count and the cards are fetched,
// and nothing is said.
// SEVERAL AT ONCE (the handoff's decision 18). A BURST is deliveries
// announced within `burstMs` (10 s) of the one before; it ends that long
// after the last. The first two that are said in a burst get their own
// toasts; from the third, those named toasts are taken away and ONE toast
// stands for the burst, "You have 3 new notes", whose "Open" leads to the
// inbox; with each further one it is put up again with the new count, so
// its 8 seconds start over. Every delivery is still announced by itself
// (`admin--notes--inbox:delivery`), with `detail.burstMs`, the length of the
// window, so that `admin--notes--alert` counts its once-per-burst chime by
// the same clock. The burst is kept beside the controller (`burst`), like
// `pending`: it outlives a Turbo visit.
//
// THIS TAB'S OWN WRITES. A signal with this tab's own `origin` is ignored
// (`live/connection`'s `TAB`; `admin--notes--live#tag` puts it on the tab's
// notes writes as `X-Notes-Tab`): "Mark all read" has drawn its change
// already. The header goes on WRITES only. A thread's GET marks deliveries
// read, and the `inbox` signal that follows must come back to this tab
// without an origin, because the sidebar's count is outside the frame that
// GET redrew.
//
// THE SOCKET. When it drops, CS Studio works as without push; when it is
// back, the count, the cards and what was to be announced are fetched once
// -- signals sent meanwhile were never received. What a session's end does
// to the socket: `live/connection`. This controller says on <body> whether
// the person's subscription is up, its half of `data-notes-live`
// (`live/state`).
//
// THE TAB'S NOTE DRAFTS are this person's or nobody's: they go when the
// person signs out (`signingOut`) and when a page is loaded for someone else
// (`connect`), here because this controller is the one that is told who the
// person is (`person`).
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
  static values = { unreadUrl: String, cardUrl: String, openThreadsUrl: String, deliveryUrl: String, person: String, burstMs: { type: Number, default: BURST_MS } }

  initialize() {
    this.timers = new Map()
    this.dropped = false
  }

  connect() {
    this.subscription = listen({ channel: "Notes::PersonChannel" }, Object.assign((signal) => this.addressed(signal), {
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
    this.subscription?.()
    this.subscription = null
    if (live === this) live = null
    // The timers go; what the person's stream said stays (`pending`).
    this.timers.forEach((timer) => clearTimeout(timer))
    this.timers.clear()
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

  // --- the socket -------------------------------------------------------------------

  // Whether the person's subscription is up: this controller's half of
  // `data-notes-live` (`live/state`; the records' subscriptions are
  // `admin--notes--live`'s half).
  sync() {
    report(this.element, "person", Boolean(this.subscription?.up))
  }

  // The person's stream is up. After a drop, what the person's signals lead
  // to is fetched once; each record's own subscription does the same for
  // its part (`admin--notes--live#recordTargetConnected`).
  online() {
    if (this.dropped) this.soon("person", () => this.inbox())
    this.dropped = false
    this.sync()
  }

  offline() {
    this.dropped = true
    this.sync()
  }

  // As `admin--notes--live#soon`, with this controller's own timers.
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


  // --- what the person's stream says ------------------------------------------------

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
    return json(url.pathname + url.search)
  }

  // In one task, with no `await`: the controller that was live when the
  // delivery had been read is the one that judges and says it.
  announce(row) {
    const now = Date.now()
    if (now - burst.last > this.burstWindow) endBurst()
    burst.last = now

    const shown = this.watching(row.thread_id)
    const detail = { id: row.id, reason: row.reason, sentence: row.sentence, title: row.title, excerpt: row.excerpt, url: row.url, threadId: row.thread_id, shown, burstMs: this.burstWindow }
    document.dispatchEvent(new CustomEvent("admin--notes--inbox:delivery", { detail }))
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

  // Whether the person is looking at that thread: `admin--notes--live`'s
  // predicate (its `watching`: the thread is the view of a notes frame of
  // this tab, and the document is not hidden), asked by an event that
  // controller answers (`watched`, through `data-action` on <body>).
  // `dispatchEvent` runs its listeners before it returns, so the answer is
  // in `detail` on the next line, in the same task (`announce` has no
  // `await`). Neither controller holds a reference to the other: no outlet,
  // no import. Should nobody answer, the answer stays false, which is the
  // safe side: a toast too many (and a chime), never a note taken as seen
  // that nobody saw. That can only be the moment of a full load in which
  // this controller is connected and `admin--notes--live` is not yet, with
  // a delivery announced in that gap -- not reachable in practice: `live`
  // stands before `inbox` in <body>'s `data-controller`, and `announce` runs
  // only after `soon`'s half second and two fetches. It is not impossible.
  watching(threadId) {
    const detail = { threadId, watching: false }
    document.dispatchEvent(new CustomEvent("admin--notes--inbox:watching", { detail }))
    return detail.watching
  }

  async refreshInbox() {
    const count = await json(this.unreadUrlValue)
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
