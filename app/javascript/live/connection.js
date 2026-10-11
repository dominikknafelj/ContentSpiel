import { cable } from "@hotwired/turbo-rails"

// The cable connection of CS Studio: one socket per document, the
// subscriptions on it shared by whoever listens, and the tab's id.
//
// WHO USES IT. The notes' two controllers on <body>:
// `controllers/admin/notes/inbox_controller.js` listens to the person's
// stream (`Notes::PersonChannel`, one per tab), and
// `controllers/admin/notes/live_controller.js` to one stream per record
// shown (`Notes::RecordChannel`). Presence's
// `controllers/admin/presence/record_controller.js` is its third user: one
// stream per record whose people are shown (`Presence::Channel`), on which
// it also sends (`perform`), and its fourth is
// `controllers/admin/presence/list_controller.js`, which listens to the
// lists' one stream (`Presence::ListChannel`). Live editing's
// `controllers/admin/editing/live_controller.js` is the fifth: one stream per
// open page or post (`Editing::Channel`), and `editing/requests` puts `TAB` on
// the writes of an editor (`X-Notes-Tab`). All of them hear signals that say only THAT something
// changed (a kind and ids) and fetch the part again themselves; nothing
// here knows what a signal means.
//
// NOTHING ON A PUBLIC PAGE IMPORTS IT. The consumer is the one bundled in
// turbo-rails; nothing but this file asks for it, so a public page opens no
// socket, and the socket is closed again when a Turbo visit leaves CS Studio
// (`listen`, `close`). The folder is pinned `preload: "admin"` and is in
// `ADMIN_ONLY` of `test/integration/public_javascript_test.rb`.
//
// A session that ended has its socket closed by the server
// (`Session#disconnect_cable`); the consumer's one reconnect is refused with
// `reconnect: false`, and it stops there, silently (`open`).

// This tab, for as long as its document lives: the shape the server echoes
// (`Live::Signals::TAB`, lower-case letters, digits and dashes, 8 to 40).
// It is what a notes write sends as `X-Notes-Tab`.
export const TAB = `tab-${Array.from(crypto.getRandomValues(new Uint8Array(16)), (byte) => byte.toString(16).padStart(2, "0")).join("")}`

// The subscriptions of this document, one per channel-and-parameters, shared
// by whoever listens. A Turbo visit replaces <body>, and with it the
// controllers that listen and their targets: the old ones let go and the new
// ones ask in the same task. Unsubscribing and subscribing again to the same
// identifier at once is what Action Cable can't promise the order of (the
// server works its commands on a pool; a late "unsubscribe" would remove the
// new subscription, and the confirmation of the old one would have been taken
// for it), so a subscription nobody listens to is let go a task later, and
// one asked for again in between is simply kept. When the last one goes, the
// tab has left CS Studio and the socket is closed.
const pool = new Map()

// Listens to the channel `params` names. `listener(signal)` is called for
// each message received; `listener.connected`, `listener.disconnected` and
// `listener.rejected`, where defined, when the subscription is confirmed,
// when the socket drops and when the server refuses it (a record the viewer
// may not read). Answers the function that stops listening, which also says
// how the subscription stands now -- `up`: confirmed and not dropped since;
// `settled`: answered, confirmed or rejected; `rejected`: refused by the
// server -- because someone who joins a subscription another listener
// already holds is told of no change.
//
// It also carries `perform(action, data)`, which sends a channel action and
// answers whether it was sent. It is sent ONLY WHILE THE SUBSCRIPTION IS UP
// and this listener still listens: Action Cable drops a `perform` on a
// socket that is not open without a word, and the server raises for a
// subscription it has not confirmed, so a caller that must not lose what it
// says sends it again at the next `connected`. An action belongs to the
// SUBSCRIPTION, not to the listener -- every listener with these params
// shares the one subscription, and the channel cannot tell them apart -- so
// whatever is sent must mean the same sent twice (presence's `report` and
// `beat` do). Each is sent with a `seq`, rising per subscription, so that a
// channel can tell which of two commands that overtook each other is older.
//
// And `suspend()` and `resume()`: see where they are defined, below.
export function listen(params, listener) {
  const key = JSON.stringify(params)
  let entry = pool.get(key)
  if (!entry) {
    entry = { listeners: new Set(), up: false, settled: false, rejected: false }
    const tell = (name, ...args) => [ ...entry.listeners ].forEach((each) => each[name]?.(...args))
    // An entry that `close` has ended hears nothing more: an answer of the
    // server's that was on its way (a confirmation, in the wait before the
    // unsubscribe is sent) must not tell its listeners `connected` after
    // they were told `disconnected`.
    const unlessClosed = (act) => (...args) => { if (!entry.closed) act(...args) }
    entry.tell = tell
    // Asks the server, now and again after a `suspend`. The subscription
    // itself, once the consumer has made it (before the server can have
    // confirmed it), is kept for `perform` and `suspend`.
    entry.subscribe = () => {
      const made = entry.subscription = cable.subscribeTo(params, {
        connected: unlessClosed(() => { entry.up = entry.settled = true; tell("connected") }),
        disconnected: unlessClosed(() => { entry.up = entry.settled = false; tell("disconnected") }),
        rejected: unlessClosed(() => { entry.rejected = entry.settled = true; tell("rejected") }),
        received: unlessClosed((signal) => [ ...entry.listeners ].forEach((each) => each(signal)))
      })
      made.then((subscription) => { if (entry.subscription === made) entry.made = subscription })
    }
    entry.subscribe()
    pool.set(key, entry)
  }
  clearTimeout(entry.release)
  entry.listeners.add(listener)

  const stop = () => {
    entry.listeners.delete(listener)
    if (entry.listeners.size > 0) return
    entry.release = setTimeout(async () => {
      const subscription = await entry.subscription
      // Ended by `close` meanwhile: the key may be another entry's by now.
      if (entry.listeners.size > 0 || entry.closed) return
      pool.delete(key)
      // A rejected one is forgotten on both sides already, and so is a
      // suspended one.
      if (!entry.rejected && !entry.suspended) subscription.unsubscribe()
      if (pool.size === 0) close()
    }, 0)
  }
  const perform = (action, data = {}) => {
    if (!entry.up || entry.closed || !entry.made || !entry.listeners.has(listener)) return false
    // Numbered, in the order of sending, per subscription: the server works a
    // connection's commands on whichever thread is free and a channel that
    // cares which came last (presence's) drops a number it has passed.
    entry.seq = (entry.seq || 0) + 1
    return entry.made.perform(action, { ...data, seq: entry.seq }) !== false
  }
  // Ends the subscription ON THE SERVER AT ONCE, in this task, and keeps the
  // listeners: `resume` asks for it again. For a document that is going
  // away (`pagehide`): a page left by a full load may be kept by the browser
  // for the Back button with its socket still open, so the server is told of
  // no close for as long as the page is kept, and `stop` lets go a task
  // later, which a page that is being frozen may never run. The listeners
  // are told `disconnected`, as when the socket drops; after `resume` they
  // are told `connected` again. Both are harmless twice.
  //
  // BOTH ARE THE SUBSCRIPTION'S, asked by one listener, as `perform` is:
  // suspending cuts off EVERY listener of these params. That is right when
  // all of them go together (every presence part of a page hears the same
  // `pagehide`), and two things follow that nothing does today: a listener
  // of another kind sharing the params would be silenced and would not come
  // back by itself; and a listener that JOINS a suspended subscription is
  // told nothing and waits for someone's `resume`.
  const suspend = () => {
    if (entry.suspended || entry.closed || entry.rejected || !entry.made || !entry.listeners.has(listener)) return
    entry.suspended = true
    entry.up = entry.settled = false
    entry.made.unsubscribe()
    entry.made = null
    entry.tell("disconnected")
  }
  const resume = () => {
    if (!entry.suspended || entry.closed || !entry.listeners.has(listener)) return
    entry.suspended = false
    entry.subscribe()
  }
  return Object.defineProperties(stop, {
    up: { get: () => entry.up }, settled: { get: () => entry.settled }, rejected: { get: () => entry.rejected },
    perform: { value: perform }, suspend: { value: suspend }, resume: { value: resume }
  })
}

// A socket the server closed for good (the session ended; someone has
// signed in again since) is opened again by the first page that asks.
export function open() {
  cable.getConsumer().then((consumer) => consumer.ensureActiveConnection())
}

// Ends every subscription and the socket. It is how the socket is closed
// when a Turbo visit leaves CS Studio: the last listener stopped, and the
// last subscription was let go (`listen`). Called with subscriptions still
// held, it ends those too: their listeners are told `disconnected`, as they
// are when the socket drops -- their subscription is not up any more, and
// one that was told nothing would go on saying it is -- and a `stop` that
// comes later finds nothing left to do. They are told ONCE and then hear
// nothing again, ever: no later `listen` revives their subscription. That
// is right for a deliberate close (the tab left CS Studio; a test) and is
// NOT a drop that recovers: to a listener it looks like one whose
// `connected` never comes, so `close` is no way to reconnect.
//
// The socket is closed only if nobody listens by then. Ending the
// subscriptions waits (for the consumer, for each subscription), and a
// `listen` that comes in that wait has made a new subscription on this
// socket: closed under it, it would never be confirmed, and nothing would
// open the socket again before the next `open`.
export async function close() {
  const entries = [ ...pool.values() ]
  pool.clear()
  entries.forEach((entry) => {
    clearTimeout(entry.release)
    entry.closed = true
    entry.up = entry.settled = false
    ;[ ...entry.listeners ].forEach((each) => each.disconnected?.())
  })
  for (const entry of entries) {
    const subscription = await entry.subscription
    if (!entry.rejected && !entry.suspended) subscription.unsubscribe()
  }
  const consumer = await cable.getConsumer()
  if (pool.size > 0) return
  consumer.disconnect()
}
