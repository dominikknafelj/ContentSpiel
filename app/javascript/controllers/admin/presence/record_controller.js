import { Controller } from "@hotwired/stimulus"
import { listen, TAB } from "live/connection"
import { settle } from "live/state"

// This tab's presence on ONE record, and the people shown for it (presence
// spec §5.2; `Admin::PresenceScreen::PeopleComponent` renders the element:
// an editor's header, the media library's image panel). It does four things,
// and nothing else:
//
// 1. SUBSCRIBES the tab to `Presence::Channel` for the record. Subscribing
//    IS arriving and unsubscribing IS leaving: the server writes and deletes
//    the tab's row. There is no "leave" to send.
// 2. SAYS HOW THE TAB IS: "away" while the document is hidden, or after
//    `idle` (5 minutes) without a key, a press, a pointer move or a scroll
//    in it; "here" otherwise. A change is reported at once (`report`), and
//    the state is said again with every keep-alive (`beat`, every 30
//    seconds), so a row the server lost comes back as what the tab is.
// 3. REDRAWS THE PEOPLE when the server says they changed, and on a slow
//    timer besides (below).
// 4. Says on its element whether its subscription has been answered
//    (`data-live-part`, `live/state`), which the system tests wait for.
//
// IT TOUCHES NOTHING OF THE EDITOR. Its element stands outside every form.
// It never visits, never changes the address, sends nothing through the
// write queue and reads nothing of it; it does not know an autosave base.
// The people are fetched with a plain `fetch`, NOT by navigating the frame:
// a Turbo request in an editor is held while a save is out
// (`saving/frame_hold.js`) and is heard by everyone who listens for Turbo's
// frame events, and who else has the page open is nobody's business there.
// The frame element is only the place the answer is put (and the id by
// which it is found in the answer).
//
// THE CHANNEL'S CONTRACT (`app/channels/presence/channel.rb`), kept here:
// - THE STATE IS REPORTED ON EVERY `connected`, the first and after every
//   reconnect, because an arrival makes the row "here" whatever the tab is;
//   and right after `listen` when the subscription is already up -- a
//   listener that joins a subscription already running is told nothing, and
//   a Turbo visit to the same record's screen keeps the subscription (it is
//   let go a task after its last listener, `live/connection`), so the server
//   sees no new arrival. Known and accepted: an away person who reconnects
//   is "here" for an instant and then "away 0 min", since the server counts
//   "away since" from the arrival.
// - `report` and `beat` mean the same sent twice: the subscription is shared
//   by every listener with these params, so a second part of the page
//   showing the same record sends them too.
// - THE PARAMS ARE BUILT IN ONE ORDER, the id as a string (`params`): the
//   pool's key is their JSON, and two spellings would be two subscriptions
//   and two rows' worth of arrivals for one record.
//
// THE TIMERS. A hidden tab's timers are throttled by the browser to about
// one run a minute; the server's stale limit (150 seconds) allows for it,
// and nothing here tries to beat the throttle.
//
// PEOPLE WHO LEFT WITHOUT SAYING SO. A crashed tab or a dropped network
// sends no leave and causes no signal: the server stops counting its row
// after 150 seconds, but a browser only learns that when it asks. So the
// people are also fetched every `refresh` (60 seconds) while the document
// is visible, when it becomes visible again, and at every `connected`.
// A hidden document fetches nothing: what it missed it reads when seen.
//
// THE INPUT LISTENERS are on the document, passive, and do next to nothing:
// they note the time, and wake the tab if it was away. `pointermove`, which
// fires with every frame of a moving mouse, is looked at once a second at
// most. Typing in the rich-text editor costs one assignment per key.
//
// WHEN THE RECORD IS GONE FOR THIS VIEWER -- the subscription is refused,
// or the frame's answer is a 404 or a 403: the record went to the trash, or
// a right was taken away while the page was open -- the part stops for
// good: nobody is shown, the timers end and it stops listening, which is
// leaving (the others stop seeing someone who can no longer read the
// record). A Turbo visit to the screen starts a new one. A session that
// ended (the answer is a redirect to the sign-in page) and a server error
// are not that: nobody is shown, and it goes on asking.
//
// ARRIVING (handoff 14 and 25): a circle that is new fades in over 150ms
// (`.admin-presence` in content-spiel.tailwind.css; not with reduced
// motion). Someone who left is simply not in the next drawing, and here to
// away is redrawn at once. The first drawing after connecting fades nobody
// in: those people did not arrive, the viewer did.
//
// A DRAWING REPLACES what the frame holds, so it is made only when the
// answer differs from the one shown: the read once a minute that finds
// nothing new touches nothing, and a screen reader is not told the group
// again. When it does differ, what a person was doing in the frame is put
// back: an open list is open again, and the focus, which can only have been
// on the group's button or in its list, is there again (on the button when
// the list is gone; nowhere when nobody is left).
//
// A TAB THAT IS GOING SAYS SO. Leaving by a Turbo visit disconnects this
// controller, which stops listening. Leaving by a full load (an address
// typed, a link out of CS Studio, signing out) disconnects nothing, and the
// browser may keep the page for its Back button with the socket still open:
// the server then hears of no close, and the person stays on the record
// until their row goes stale. So on `pagehide` the subscription is ended at
// once (`suspend`, `live/connection`), and taken up again on `pageshow` if
// the page comes back. `pagehide` comes before the document is hidden, so
// the "away" of a page on its way out is never sent: it would reach the
// server beside the leave, and a report that finds no row puts one back.
//
// TURBO'S SNAPSHOT keeps the page as it was left: the people of then, and a
// part that says "answered". It cannot be emptied as the page is left --
// `turbo:before-cache` also fires when a frame navigation is promoted to a
// history entry, with the page staying where it is, and a promoted frame's
// snapshot is taken before that event anyway. So, as the toasts do
// (`admin--ui--toast`), what comes OUT of the cache has its people taken
// out before it reaches the page: a preview and a restoration (Back,
// Forward), for as long as that visit lasts. The server's own rendering, in a fresh page, is left alone, and
// either way the people are read again on connecting. The listeners are
// document-level and installed once, when this module first loads.
let restoring = false
document.addEventListener("turbo:visit", (event) => { restoring = event.detail.action === "restore" })
// The visit is over: a render that comes without a visit of its own (a form
// answered in place) is no restoration.
document.addEventListener("turbo:load", () => { restoring = false })
document.addEventListener("turbo:before-render", (event) => {
  if (!restoring && !document.documentElement.hasAttribute("data-turbo-preview")) return
  event.detail.newBody.querySelectorAll("[data-controller~='admin--presence--record']").forEach((part) => {
    part.setAttribute("data-live-part", "waiting")
    part.removeAttribute("data-presence-drawn")
    part.querySelector("[data-admin--presence--record-target='frame']")?.replaceChildren()
  })
})

const COALESCE = 500
const MOVE_EVERY = 1000
const INPUTS = [ "keydown", "pointerdown", "scroll" ]

export default class extends Controller {
  static targets = [ "frame" ]
  static values = {
    kind: String, id: String, url: String,
    idle: { type: Number, default: 300000 }, beat: { type: Number, default: 30000 }, refresh: { type: Number, default: 60000 }
  }

  connect() {
    this.lastInput = this.lastMove = Date.now()
    this.state = document.hidden ? "away" : "here"
    this.drawn = false
    this.shown = null
    this.element.removeAttribute("data-presence-drawn")
    this.element.removeAttribute("data-presence-gone")

    this.input = () => this.active(Date.now())
    this.move = () => {
      const now = Date.now()
      if (now - this.lastMove < MOVE_EVERY) return
      this.lastMove = now
      this.active(now)
    }
    this.visibility = () => this.seen()
    this.left = () => this.closeList()
    this.going = () => this.stop.suspend()
    this.back = () => this.stop.resume()
    // Captured: a scroll does not bubble, and most of an editor's scrolling
    // is the window's, some an inner box's.
    INPUTS.forEach((name) => document.addEventListener(name, this.input, { passive: true, capture: true }))
    document.addEventListener("pointermove", this.move, { passive: true, capture: true })
    document.addEventListener("visibilitychange", this.visibility)
    window.addEventListener("pagehide", this.going)
    window.addEventListener("pageshow", this.back)

    const listener = Object.assign((signal) => this.heard(signal), {
      connected: () => this.arrived(), disconnected: () => this.answered(), rejected: () => this.gone()
    })
    this.stop = listen(this.params, listener)
    this.running = true
    if (this.stop.rejected) return this.gone()
    this.stop.up ? this.arrived() : this.answered()
    this.watchIdle()
    this.keepAlive()
    this.keepFresh()
  }

  disconnect() {
    this.quit()
    // The element has left the document: the page's answer no longer waits
    // for it.
    settle(document.body)
  }

  // Everything this part set going is ended: its listeners, its timers, a
  // request that is out, and the subscription (which is leaving).
  quit() {
    if (!this.running) return
    this.running = false
    INPUTS.forEach((name) => document.removeEventListener(name, this.input, { capture: true }))
    document.removeEventListener("pointermove", this.move, { capture: true })
    document.removeEventListener("visibilitychange", this.visibility)
    window.removeEventListener("pagehide", this.going)
    window.removeEventListener("pageshow", this.back)
    this.frameTarget.removeEventListener("mouseleave", this.left)
    clearTimeout(this.idleTimer)
    clearInterval(this.beatTimer)
    clearInterval(this.refreshTimer)
    clearTimeout(this.soonTimer)
    this.soonTimer = null
    this.request?.abort()
    this.stop()
  }

  // The record is gone for this viewer (see WHEN THE RECORD IS GONE): nobody
  // is shown and the part stops. It has nothing left to wait for, so the
  // page's answer does not wait for it either.
  gone() {
    this.quit()
    this.shown = null
    this.frameTarget.replaceChildren()
    this.element.setAttribute("data-live-part", "answered")
    this.element.setAttribute("data-presence-gone", "true")
    settle(document.body)
  }

  // One order, the id a string: see THE PARAMS above.
  get params() {
    return { channel: "Presence::Channel", type: this.kindValue, id: String(this.idValue), tab: TAB }
  }

  // A test shortens these on the element; a change takes effect at once.
  idleValueChanged() { if (this.running) this.watchIdle() }
  beatValueChanged() { if (this.running) this.keepAlive() }
  refreshValueChanged() { if (this.running) this.keepFresh() }

  // --- the subscription --------------------------------------------------

  // Confirmed (or found already up): say what the tab is, and read who is
  // here -- someone may have come between the page's rendering and now, and
  // whatever was signalled while the socket was down was not heard.
  arrived() {
    this.stop.perform("report", { state: this.state })
    this.answered()
    this.fetchPeople()
  }

  // This part's word in `data-notes-live`: answered once the server has
  // confirmed or refused the subscription, waiting again when it drops.
  answered() {
    this.element.setAttribute("data-live-part", this.stop.settled ? "answered" : "waiting")
    settle(document.body)
  }

  // --- here and away -----------------------------------------------------

  // Something was done in the tab.
  active(now) {
    this.lastInput = now
    if (this.state === "away" && !document.hidden) {
      this.become("here")
      this.watchIdle()
    }
  }

  become(state) {
    if (state === this.state) return
    this.state = state
    // Not sent while the subscription is down: `arrived` says it then.
    this.stop.perform("report", { state })
  }

  // One timer, for the moment the tab will have been idle long enough; it
  // asks again then, since input has usually moved that moment on.
  watchIdle() {
    clearTimeout(this.idleTimer)
    if (this.state === "away") return
    const left = this.idleValue - (Date.now() - this.lastInput)
    if (left <= 0) return this.become("away")
    this.idleTimer = setTimeout(() => this.watchIdle(), left)
  }

  // `visibilitychange`: hidden is away; seen again is here, with the idle
  // time starting over, and the people are read once for whatever was
  // missed.
  seen() {
    if (document.hidden) {
      clearTimeout(this.idleTimer)
      return this.become("away")
    }
    this.lastInput = Date.now()
    this.become("here")
    this.watchIdle()
    this.fetchPeople()
  }

  keepAlive() {
    clearInterval(this.beatTimer)
    this.beatTimer = setInterval(() => this.stop.perform("beat", { state: this.state }), this.beatValue)
  }

  // --- the people --------------------------------------------------------

  keepFresh() {
    clearInterval(this.refreshTimer)
    this.refreshTimer = setInterval(() => this.fetchPeople(), this.refreshValue)
  }

  // A signal says only THAT the record's people changed. Several in a row
  // (someone reloads: a leave and an arrival) are one fetch.
  heard(signal) {
    if (signal?.kind !== "presence" || this.soonTimer) return
    this.soonTimer = setTimeout(() => {
      this.soonTimer = null
      this.fetchPeople()
    }, COALESCE)
  }

  // The frame, asked of the server again. Never in a hidden document. A
  // newer request ends an older one. A 404 or a 403 ends the part (`gone`);
  // any other refusal (the session ended and the answer is the sign-in page,
  // a server error) shows nobody; a network error leaves what is shown; and
  // an answer that is the one already shown is not drawn again.
  async fetchPeople() {
    if (document.hidden || !this.running) return
    this.request?.abort()
    const request = this.request = new AbortController()
    let answer = null
    let refused = false
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "text/html", "Turbo-Frame": this.frameTarget.id }, signal: request.signal })
      refused = response.status === 404 || response.status === 403
      if (response.ok && !response.redirected) answer = await response.text()
    } catch (error) {
      return
    }
    if (request.signal.aborted || !this.running) return
    if (refused) return this.gone()
    if (answer !== null && answer === this.shown) return

    const fresh = answer === null ? null : new DOMParser().parseFromString(answer, "text/html").getElementById(this.frameTarget.id)
    this.shown = fresh ? answer : null
    this.put(fresh ? [ ...fresh.childNodes ] : [])
  }

  // Puts an answer in the frame, and puts back what the person was doing
  // there (see A DRAWING REPLACES).
  put(nodes) {
    const frame = this.frameTarget
    const before = people([ frame ])
    const panel = "[data-admin--ui--menu-target='panel']"
    const focused = frame.contains(document.activeElement)
    const reading = focused && Boolean(document.activeElement.closest(panel))
    const open = Boolean(frame.querySelector(`${panel}:not([hidden])`))

    frame.replaceChildren(...nodes.map((node) => document.importNode(node, true)))

    if (this.drawn) this.circles.filter((each) => !before.has(each.dataset.presenceUser)).forEach((each) => each.setAttribute("data-presence-arriving", ""))
    this.drawn = true
    // Said on the element, for whoever has to know that the people shown
    // are this connection's own reading (a test, before it counts fades).
    this.element.setAttribute("data-presence-drawn", "true")
    const button = frame.querySelector("[data-admin--ui--menu-target='button']")
    const list = frame.querySelector(panel)
    // The list, open again: for someone reading it, or for the pointer that
    // is still on the group. The new list has never seen the pointer come,
    // so it would not see it go either (the browser tells an element that
    // the pointer left only if it told it that it came): the frame, which
    // stays, is asked instead, once.
    frame.removeEventListener("mouseleave", this.left)
    if (open && list && (reading || frame.matches(":hover"))) {
      list.removeAttribute("hidden")
      button.setAttribute("aria-expanded", "true")
      if (!reading) frame.addEventListener("mouseleave", this.left, { once: true })
    }
    if (focused) (reading && open && list ? list : button)?.focus()
  }

  // The pointer left a list that a drawing had opened again: closed, unless
  // someone is reading it by now.
  closeList() {
    const frame = this.frameTarget
    if (frame.contains(document.activeElement)) return
    frame.querySelector("[data-admin--ui--menu-target='panel']")?.setAttribute("hidden", "")
    frame.querySelector("[data-admin--ui--menu-target='button']")?.setAttribute("aria-expanded", "false")
  }

  get circles() { return [ ...this.frameTarget.querySelectorAll("[data-presence-user]") ] }
}

// The ids of everyone a drawing names: the circles and the "+N" list's rows.
function people(nodes) {
  const ids = new Set()
  for (const node of nodes) {
    if (node.nodeType !== Node.ELEMENT_NODE) continue
    node.querySelectorAll("[data-presence-user]").forEach((each) => ids.add(each.dataset.presenceUser))
    node.querySelectorAll("[data-presence-listed]").forEach((each) => ids.add(each.dataset.presenceListed))
  }
  return ids
}
