import { Controller } from "@hotwired/stimulus"
import { listen } from "live/connection"
import { settle } from "live/state"

// The markers of ONE list (presence spec §5.1, handoff 9 to 12 and 27): the
// page tree and the posts list, each of whose rows holds a marker that says
// whether someone else is working on that record
// (`Admin::PresenceScreen::RowMarkerComponent`, always rendered, `hidden`
// where nobody is). The server draws the markers with the list; this keeps
// them true afterwards. It is on the list's root, beside whatever else that
// element is (the tree's own script), and it does three things:
//
// 1. LISTENS to `Presence::ListChannel`, the one stream every list shares
//    (one fixed set of params, so every list of a page shares one
//    subscription). Its signal says only THAT presence changed somewhere:
//    it names no record, because any signed-in person may listen and a name
//    would tell them of records they may not read. So this cannot know
//    whether a signal concerns a row it shows.
// 2. READS ITS MARKERS AGAIN (`url`, the `here` address: the ids of every
//    marker it holds, answered for the readable ones with someone here) on
//    any signal -- but RARELY: no sooner than `interval` (5 seconds) after
//    its last reading, with ONE more reading afterwards if signals arrived
//    meanwhile. A busy site signals all the time; a list asks at most once
//    in five seconds whatever happens.
// 3. Says on its element whether its subscription has been answered
//    (`data-live-part`, `live/state`), which the system tests wait for.
//
// IT TOUCHES NOTHING BUT ITS MARKERS: of each, the `hidden`, the count and
// the one text (for a screen reader and in the tooltip), and only where they
// differ from what is shown, so a reading that finds nothing new changes
// nothing and no row is ever redrawn. Everything is put in as TEXT
// (`textContent`): a name is what a person typed. The words come from the
// server ready-made (`label`), the same that worded the first
// drawing; this script holds none.
//
// THE MARKERS ARE STIMULUS TARGETS, read from the document each time: the
// tree is replaced as a whole by a Turbo Stream after a move or a save, the
// posts table with its frame, and a marker kept in a variable would be one
// that is no longer in the page. When the list's own element is replaced
// (the tree's frame is), the old controller hands its clock to the new one
// (`handover`): the replacement comes from the server with fresh markers
// and asks nothing by itself, a reading that was owed is still made, and
// the interval is still kept.
//
// THE READING is a plain `fetch`, not a Turbo request, for the reason the
// record's part gives (`record_controller.js`): Turbo's requests are held
// while a save is out (`saving/frame_hold.js`) and heard by everyone who
// listens for Turbo's events. An older answer never overwrites a newer one
// (a new reading ends the one before it). An error, or an answer that is
// the sign-in page (the session ended), leaves the markers as they are; the
// next tick asks again.
//
// WHEN IT READS, besides a signal:
// - when its subscription is CONFIRMED, the first time and after every
//   reconnect: what was signalled between the page's rendering and then,
//   or while the socket was down, was not heard. (A list that joins a
//   subscription already up -- a Turbo visit keeps it -- was rendered just
//   now and asks nothing.)
// - every `refresh` (60 seconds): a crashed tab sends no leave and causes
//   no signal; the server stops counting its row after 150 seconds, and a
//   list only learns that by asking.
// - when it comes OUT OF TURBO'S CACHE (Back, Forward, a preview): the
//   markers are those of then. A list this script has seen before carries
//   `data-presence-reads`, which the server never renders.
// NEVER WHILE THE DOCUMENT IS HIDDEN: what was owed is read once when it
// is seen again.
//
// HOW MANY IDS. The `here` address answers for at most 500 ids. The posts
// list shows 50 rows to a page; the tree shows every page there is, with no
// limit, so a longer list asks in several requests of 500, one after the
// other, and draws when all have answered.
//
// SEVERAL LISTS ON ONE PAGE share the one subscription, and each reads for
// its own markers at its own pace. (Today a page holds one: the tree, or
// the posts table.)
//
// `data-presence-reads` on the element counts the readings that were
// drawn, for a test that has to know one is over.
const SETTLE = 500

// What a list whose element was replaced leaves for the one that takes its
// place: when it last read, and whether a reading is owed.
const handover = new Map()

export default class extends Controller {
  static targets = [ "marker" ]
  static values = {
    kind: String, url: String,
    interval: { type: Number, default: 5000 }, refresh: { type: Number, default: 60000 },
    // How many ids one request asks about: what the `here` address answers
    // for. The server sends the real number (`Presence::HERE_IDS`, rendered
    // where the list is drawn); 500 is only the fallback. A value so that a
    // test can see a long list asked in parts without drawing 501 rows.
    chunk: { type: Number, default: 500 }
  }

  connect() {
    const left = handover.get(this.key)
    handover.delete(this.key)
    this.last = left?.last || 0
    // Seen by this script before: out of Turbo's cache (see WHEN IT READS).
    this.due = Boolean(left?.due) || this.element.hasAttribute("data-presence-reads")
    this.element.setAttribute("data-presence-reads", "0")

    this.visibility = () => { if (!document.hidden) this.schedule() }
    document.addEventListener("visibilitychange", this.visibility)

    const listener = Object.assign((signal) => this.heard(signal), {
      connected: () => this.confirmed(), disconnected: () => this.answered(), rejected: () => this.answered()
    })
    this.stop = listen({ channel: "Presence::ListChannel" }, listener)
    this.running = true
    this.answered()
    this.keepFresh()
    this.schedule()
  }

  disconnect() {
    this.running = false
    handover.set(this.key, { last: this.last, due: this.due })
    document.removeEventListener("visibilitychange", this.visibility)
    clearTimeout(this.timer)
    this.timer = null
    clearInterval(this.refreshTimer)
    this.request?.abort()
    this.stop()
    // The element has left the document: the page's answer no longer waits
    // for it.
    settle(document.body)
  }

  // Which list this is, for the one that replaces it.
  get key() { return `${this.kindValue} ${this.urlValue}` }

  // A test shortens this on the element; the change takes effect at once.
  // (`interval` is read each time it is used.)
  refreshValueChanged() { if (this.running) this.keepFresh() }

  // --- the subscription ----------------------------------------------------

  // Confirmed, the first time or again after the socket was down.
  confirmed() {
    this.answered()
    this.owe()
  }

  // This part's word in `data-notes-live`: answered once the server has
  // confirmed or refused the subscription, waiting again when it drops.
  answered() {
    this.element.setAttribute("data-live-part", this.stop.settled ? "answered" : "waiting")
    settle(document.body)
  }

  // "Presence changed somewhere."
  heard(signal) {
    if (signal?.kind === "presence") this.owe()
  }

  // --- when to read --------------------------------------------------------

  keepFresh() {
    clearInterval(this.refreshTimer)
    this.refreshTimer = setInterval(() => this.owe(), this.refreshValue)
  }

  // A reading is owed. However often this is said, one is made.
  owe() {
    this.due = true
    this.schedule()
  }

  // One timer, for the moment the owed reading may be made: `interval` after
  // the last one, and never at once -- a person who reloads leaves and
  // arrives within a moment, and the reading waits for both. A hidden
  // document sets none: `visibilitychange` comes here again.
  schedule() {
    if (!this.running || !this.due || this.timer || document.hidden) return
    const wait = Math.max(SETTLE, this.intervalValue - (Date.now() - this.last))
    this.timer = setTimeout(() => {
      this.timer = null
      if (this.due && !document.hidden) this.read()
    }, wait)
  }

  // --- the reading ---------------------------------------------------------

  async read() {
    this.due = false
    this.last = Date.now()
    const ids = [ ...new Set(this.markerTargets.map((marker) => marker.dataset.presenceId)) ]
    if (ids.length === 0) return

    this.request?.abort()
    const request = this.request = new AbortController()
    const here = {}
    try {
      const chunk = Math.max(1, this.chunkValue)
      for (let from = 0; from < ids.length; from += chunk) {
        const url = new URL(this.urlValue, document.baseURI)
        ids.slice(from, from + chunk).forEach((id) => url.searchParams.append("ids[]", id))
        const response = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin", signal: request.signal })
        if (!response.ok || response.redirected) return
        Object.assign(here, await response.json())
      }
    } catch (error) {
      return
    }
    if (request.signal.aborted || !this.running) return

    this.draw(new Set(ids), here)
    this.element.setAttribute("data-presence-reads", String(Number(this.element.getAttribute("data-presence-reads") || 0) + 1))
    // Signals that came while it was out are owed a reading of their own.
    this.schedule()
  }

  // The answer, put on the markers that were asked about and are still (or
  // again) in the list. A marker that came with a redraw meanwhile and was
  // not asked about is the server's own and is left alone.
  draw(asked, here) {
    this.markerTargets.forEach((marker) => {
      const id = marker.dataset.presenceId
      if (!asked.has(id)) return
      const answer = here[id]
      show(marker, Number(answer?.count) || 0, String(answer?.label || ""))
    })
  }
}

// One marker, as answered: nothing is written that is already there.
function show(marker, count, label) {
  const parts = {
    count: marker.querySelector("[data-presence-marker-count]"),
    label: marker.querySelector("[data-presence-marker-label]"),
    tip: marker.querySelector("[data-tooltip]")
  }
  const said = count > 0 && label ? `${parts.label?.dataset.presenceLead || ""}${label}` : ""
  put(parts.count, count > 1 ? String(count) : "")
  put(parts.label, said)
  put(parts.tip, count > 0 ? label : "")
  if (parts.count && parts.count.hidden !== count < 2) parts.count.hidden = count < 2
  if (marker.dataset.presenceCount !== String(count)) marker.dataset.presenceCount = String(count)
  if (marker.hidden !== (count === 0)) marker.hidden = count === 0
}

function put(element, text) {
  if (element && element.textContent !== text) element.textContent = text
}
