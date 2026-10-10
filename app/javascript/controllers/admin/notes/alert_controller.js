import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// A mention's chime and desktop notification (notes spec §6.4, D18, D19).
// Lives on <body>. `admin--notes--live` announces every delivery it has READ
// through the scoped endpoint (`admin--notes--live:delivery` on `document`; a
// delivery the person may no longer read is never announced, so nothing here
// can speak of one); this acts on a `mention` only, and only as the person's
// two settings say (`sound`, `desktop`: the account screen's switches, as
// they were when this page was drawn).
//
// THE RULE, for one mention and all the tabs this person has open in this
// browser:
// - A tab is LOOKING AT the thread (`detail.shown`, which is
//   `admin--notes--live#watching`, the one predicate: the thread is open
//   there and the document is not hidden): nobody chimes and nobody
//   notifies, in any tab. The person has seen it arrive.
// - Otherwise exactly ONE tab chimes, if the sound setting is on: a visible
//   one, else the first to claim it.
// - And exactly one raises the desktop notification, if that setting is on,
//   this browser has granted the permission, and NO tab of theirs is
//   visible: with CS Studio in view the toast has said it already.
//
// HOW THE TABS AGREE. Every tab hears the same signal, each in its own time
// (a hidden tab's timers are slowed by the browser, by a second or more). So
// they speak over a `BroadcastChannel` named after the person:
// - A tab whose delivery arrived says CLAIM, with the delivery's id, its
//   thread, the time, and whether the tab is visible and looking at the
//   thread.
// - A VISIBLE tab that hears a claim for a delivery of which its own copy is
//   still on its way answers with a claim of its own at once: what it is --
//   visible, perhaps looking at the thread -- must count now, not when its
//   signal arrives, and a chime needs nothing the delivery says. A hidden
//   tab has nothing to add and stays quiet.
// - `AGREE_MS` after its claim each tab decides from the claims it holds.
//   One of them is looking at the thread: nothing. Else the winner is the
//   visible claim, else the earliest (the time, then the tab's id, so every
//   tab picks the same one); the winner says DONE and alerts, the others do
//   nothing.
// - A tab that has heard DONE for a delivery never alerts for it, however
//   late its own copy of the signal comes.
// Without `BroadcastChannel`, or where one cannot be made, each tab decides alone.
// A LIMIT, known: a visible tab that is busy for longer than `AGREE_MS` (a
// long task, a slow frame) cannot answer a claim in time. A hidden tab may
// then chime and notify the desktop although CS Studio is in view.
//
// ONCE PER BURST (the handoff's decision 18). Several notes at once make one
// sound: within a burst -- deliveries within `burstMs` (10 s) of the one
// before, `admin--notes--live`'s clock, handed over as `detail.burstMs` --
// only the first mention that would chime does, and only the first that
// would notify the desktop does. DONE says whether its tab chimed and
// notified, so every tab knows the burst has had its sound whichever of
// them made it; the burst ends `burstMs` after the last thing this tab heard
// of one (a delivery of its own, or another tab's word).
//
// What the tabs have said is kept beside the controller, not on it: a Turbo
// visit replaces <body> and this controller with it, and a decision that was
// 150 ms away must still be made, once, from everything that was heard.
//
// THE CHIME: two short tones from the Web Audio API; no file. A tab that has
// not had a click plays nothing, and nothing is queued for later: a context
// the browser will not start within a second is closed again.
// THE DESKTOP NOTIFICATION: its title is the inbox's sentence ("Dana
// mentioned you"), its body the record's title and the note's first 140
// characters, as plain text, exactly as the scoped endpoint gave them; a
// click brings the tab forward and opens the thread (the toast's "Open").
//
// `admin--notes--alert:settled` on `document` (`detail: { id, chimed,
// notified }`) says that this tab has made up its mind about a delivery and
// what it did: when it decides, and for a delivery announced here that needs
// no deciding (not a mention, both settings off, DONE heard before).
const AGREE_MS = 150
const TONES = [ [ 880, 0 ], [ 1175, 0.14 ] ]
const TONE_SECONDS = 0.16
const START_MS = 1000

// This tab, for as long as its document lives.
const TAB = Array.from(crypto.getRandomValues(new Uint8Array(16)), (byte) => byte.toString(16).padStart(2, "0")).join("")

// Delivery id => (tab => its claim), until someone has said DONE; and the
// deliveries someone has finished with.
const claims = new Map()
const done = new Set()

// The burst as this tab knows it (see "ONCE PER BURST"): when it last heard
// of a delivery, how long a burst's window is, and whether the burst has had
// its chime and its notification -- from this tab or, by DONE, another.
const quiet = { last: 0, ms: 10000, chimed: false, notified: false }

function arrival(ms) {
  if (Number.isFinite(ms) && ms > 0) quiet.ms = ms
  const now = Date.now()
  if (now - quiet.last > quiet.ms) quiet.chimed = quiet.notified = false
  quiet.last = now
}

// The channels of this document, one per name, shared by successive <body>s
// and closed a task after the last listener left: a visit's old controller
// leaves and its new one joins in the same task, and nothing said in between
// may be missed.
const rooms = new Map()

function join(name, listener) {
  let room = rooms.get(name)
  if (!room) {
    // The constructor can throw although the name exists (a document with an
    // opaque origin): then there is no room, and the tab decides alone, as
    // it does without `BroadcastChannel` -- never an error on <body>.
    let channel
    try {
      channel = new BroadcastChannel(name)
    } catch {
      return null
    }
    room = { channel, listeners: new Set(), closed: false }
    room.channel.addEventListener("message", (event) => [ ...room.listeners ].forEach((each) => each(event.data)))
    room.leave = (leaving) => {
      room.listeners.delete(leaving)
      if (room.listeners.size > 0) return
      room.release = setTimeout(() => {
        if (room.listeners.size > 0) return
        rooms.delete(name)
        room.closed = true
        room.channel.close()
      }, 0)
    }
    rooms.set(name, room)
  }
  clearTimeout(room.release)
  room.listeners.add(listener)
  return room
}

function note(claim) {
  if (!claims.has(claim.id)) claims.set(claim.id, new Map())
  claims.get(claim.id).set(claim.tab, claim)
}

// Visible before hidden, then the earliest, then by the tab's id.
const precedence = (one, other) => (Number(other.visible) - Number(one.visible)) || (one.at - other.at) || (one.tab < other.tab ? -1 : 1)

function shut(audio) {
  try {
    Promise.resolve(audio.close?.()).catch(() => {})
  } catch {
    // Closed already.
  }
}

// Whether a chime was asked for. Nothing before a click in this tab; and a
// context the browser holds back (no way to ask about a click here) is given
// a second to start, then closed -- never left to sound at the next click.
// A browser that cannot make the sound at all (no audio device, a context
// too many: the constructor throws) makes none, and that is all: the
// notification and the tabs' agreement go on (`decide`).
function chime() {
  try {
    return sound()
  } catch {
    return false
  }
}

function sound() {
  const Context = window.AudioContext || window.webkitAudioContext
  if (!Context) return false
  if (navigator.userActivation && !navigator.userActivation.hasBeenActive) return false

  const audio = new Context()
  let late = false
  const giveUp = setTimeout(() => {
    late = true
    shut(audio)
  }, START_MS)
  Promise.resolve(audio.resume?.()).then(() => {
    if (late) return
    clearTimeout(giveUp)

    const now = audio.currentTime
    let last = null
    TONES.forEach(([ frequency, at ]) => {
      const oscillator = audio.createOscillator()
      const gain = audio.createGain()
      oscillator.frequency.value = frequency
      gain.gain.setValueAtTime(0.0001, now + at)
      gain.gain.exponentialRampToValueAtTime(0.12, now + at + 0.02)
      gain.gain.exponentialRampToValueAtTime(0.0001, now + at + TONE_SECONDS)
      oscillator.connect(gain)
      gain.connect(audio.destination)
      oscillator.start(now + at)
      oscillator.stop(now + at + TONE_SECONDS)
      last = oscillator
    })
    last.addEventListener("ended", () => shut(audio))
  }).catch(() => {})
  return true
}

// Whether a notification was raised. The permission is this browser's and
// is only ever asked for on the account screen, in a click.
function notify(delivery) {
  if (!("Notification" in window) || window.Notification.permission !== "granted") return false

  try {
    const notification = new window.Notification(delivery.sentence, { body: `${delivery.title}\n${delivery.excerpt}`, tag: `cs-note-${delivery.id}` })
    notification.addEventListener("click", () => {
      window.focus()
      notification.close()
      Turbo.visit(delivery.url)
    })
    return true
  } catch {
    // A browser that has the constructor and refuses it (Chrome on Android
    // wants a service worker): no notification, and no error of the page's.
    return false
  }
}

export default class extends Controller {
  static targets = [ "settings" ]
  static values = { sound: Boolean, desktop: Boolean, person: String }

  initialize() {
    this.heard = this.heard.bind(this)
  }

  connect() {
    this.room = "BroadcastChannel" in window ? join(`cs-notes-alerts-${this.personValue}`, this.heard) : null
  }

  // The room is kept in hand: a decision of this controller's that is still
  // to come says DONE through it, if the next page kept it open.
  disconnect() {
    this.room?.leave(this.heard)
  }

  // THE TWO SETTINGS, KEPT CURRENT. They stand on <body>, which lives as long
  // as the tab (CS Studio moves between screens inside `#content`), so the
  // values of the page load went stale when the account screen saved new
  // ones. The server's word for them is the `settings` element: in the
  // layout it says what <body> says; the account screen's save replaces it
  // (a stream), and the one that connects then is taken -- by this tab, and
  // passed to the person's other tabs over the room they already share, so
  // none of them alerts, or wins the agreement, by an old setting. The room
  // is this browser's, which is where the two settings act (the chime and
  // the notification happen here); a tab in another browser has them with
  // its next page load, as every tab had before.
  settingsTargetConnected(element) {
    this.take(element.dataset.sound === "true", element.dataset.desktop === "true", { tell: true })
  }

  take(sound, desktop, { tell = false } = {}) {
    if (sound === this.soundValue && desktop === this.desktopValue) return
    this.soundValue = sound
    this.desktopValue = desktop
    if (tell) this.say({ type: "settings", sound, desktop })
  }

  // `admin--notes--live:delivery` on the document.
  delivery(event) {
    const delivery = event.detail
    arrival(delivery.burstMs)
    if (delivery.reason !== "mention" || !(this.soundValue || this.desktopValue) || done.has(delivery.id)) return this.settled(delivery.id)
    // Claimed already, on another tab's word (`heard`): that decision stands
    // or is still to come, and says so itself.
    if (claims.get(delivery.id)?.has(TAB)) return

    this.claim(delivery.id, delivery.threadId, delivery.shown, delivery)
  }

  heard(message) {
    // Another tab of this person saved the settings: two booleans, nothing else.
    if (message?.type === "settings") return this.take(message.sound === true, message.desktop === true)
    if (message?.type === "done") {
      arrival()
      done.add(message.id)
      claims.delete(message.id)
      // The burst has had its sound, whoever made it.
      if (message.chimed) quiet.chimed = true
      if (message.notified) quiet.notified = true
    } else if (message?.type === "claim" && !done.has(message.id)) {
      arrival()
      note(message)
      // In view, with this tab's own copy still to come: it counts now.
      if (!document.hidden && !claims.get(message.id).has(TAB)) this.claim(message.id, message.thread, this.watching(message.thread), null)
    }
  }

  claim(id, thread, watching, delivery) {
    const claim = { type: "claim", id, thread, tab: TAB, at: Date.now(), visible: !document.hidden, watching }
    note({ ...claim, delivery })
    this.say(claim)
    if (this.room) setTimeout(() => this.decide(id), AGREE_MS)
    else this.decide(id)
  }

  decide(id) {
    const held = [ ...(claims.get(id)?.values() || []) ]
    if (done.has(id) || held.length === 0) return this.settled(id)

    const watched = held.some((claim) => claim.watching)
    const mine = held.find((claim) => claim.tab === TAB)
    // Someone else's to do. The claims are kept until they say DONE: a claim
    // that comes in between must find this tab's, not draw a second one.
    if (!watched && held.sort(precedence)[0] !== mine) return this.settled(id)

    done.add(id)
    claims.delete(id)
    // Each once per burst. The notification only with no tab in view, so
    // only ever by a tab that claimed from its own delivery -- a visible tab
    // is the only one that claims without.
    const chimed = !watched && this.soundValue && !quiet.chimed && chime()
    const notified = !watched && this.desktopValue && !quiet.notified && !held.some((claim) => claim.visible) && Boolean(mine.delivery) && notify(mine.delivery)
    if (chimed) quiet.chimed = true
    if (notified) quiet.notified = true
    this.say({ type: "done", id, chimed, notified })
    this.settled(id, { chimed, notified })
  }

  say(message) {
    if (!this.room || this.room.closed) return
    this.room.channel.postMessage(message)
  }

  // `admin--notes--live#watching`, the one predicate, for a thread another tab
  // names.
  watching(thread) {
    return Boolean(this.application.getControllerForElementAndIdentifier(this.element, "admin--notes--live")?.watching(thread))
  }

  settled(id, { chimed = false, notified = false } = {}) {
    document.dispatchEvent(new CustomEvent("admin--notes--alert:settled", { detail: { id, chimed, notified } }))
  }
}
