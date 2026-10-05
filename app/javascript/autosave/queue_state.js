// What the write queue's modules share: the page generations, the queue's
// chain and its counters, the registered autosave forms, and the promotion
// window. `autosave/queue.js` has the overview and the module map.
//
// This module imports nothing and registers no listener. It is the first of
// the queue's modules to be evaluated, whichever of them is imported first,
// so the others can call it at any time. Each piece of state is a `let` or a
// collection private to this file -- an importer cannot assign to another
// module's binding, and there is ONE of each per document -- behind the small
// functions below; each says who writes it.
//
// PAGE GENERATIONS. A task belongs to the page its FORM was rendered on, not
// to the moment it was queued (fix round 4): a controller reads
// `currentGeneration()` when it connects and hands it to `enqueue`, and the
// task is told `isCurrent()`. One that belongs to a replaced page is still
// SENT -- a debounced edit is not lost to Back/Forward, a restoration visit
// having no `before-visit` to drain on -- but renders no streams and writes no
// bases into the NEW document, whose `page-base-updated-at` has the same id.
// That holds whether the page was replaced while the answer was on its way,
// while the task waited its turn (a drain that timed out leaves tasks behind),
// or BEFORE the task was even queued: as Turbo swaps the body, the field that
// still holds focus gets a `focusout`, after `turbo:before-render`, and the
// outgoing form's own action is still bound -- stamped at queue time, that
// save counted as the new page's and drew its 409 bar there (a false "Changed
// elsewhere" after Publish). The chain is never reset: the new page's first
// request waits for the old page's in-flight one.
//
// WHAT A GENERATION IS (final fix wave 1). The document an editor lives in is
// replaced in exactly two ways, and a generation names both: the `<body>`
// ELEMENT it was rendered into (a Turbo page render puts a new one in), and
// the number of times the `#content` frame has been rendered since
// (`frameRenders`: a frame navigation keeps the body and swaps the editor).
// It is deliberately NOT a count of `turbo:before-render` events, which it
// used to be: Turbo fires that event a second time, for a visit that renders
// nothing (`willRender: false`), after every REDIRECTED visit
// (`Visit#followRedirect` -- the sidebar's Pages link answers with a redirect
// to Home's editor) and when a frame navigation is promoted to a visit
// (`proposeVisitIfNavigatedWithAction` -- every tree link). The forms that had
// just connected were left a generation behind for good: every answer thrown
// away as stale, the status stuck on "Saving…", no base written back, and
// every edit after the first refused 409 without a word.
// The body's identity cannot be miscounted. One thing it cannot say is that a
// body is ABOUT to be replaced: between `turbo:before-render` and the swap an
// answer would still be drawn (a stream is applied on the next frame -- into
// the new document). So a body is also `retired` at `turbo:before-render`,
// when Turbo's current visit says it will render. That reads a Turbo internal
// (`Turbo.navigator.currentVisit.willRender`, turbo-rails 2.0.23), and only
// an explicit `true` retires: were it ever to go away, nothing is retired
// early and the identity check alone still holds.
//
// (Turbo's morphing page refresh keeps the forms and the body, and would
// retire that body: forms a generation behind for good. CS Studio does not use
// it; whoever turns it on must re-stamp the controllers.)

// See "WHAT A GENERATION IS".
let frameRenders = 0
const retired = new WeakSet()

// The page a controller was rendered on: read in `connect()`, handed back to
// `enqueue`. Opaque to the caller.
export function currentGeneration() { return { body: document.body, frame: frameRenders } }

// Whether that page is still the one showing.
export function isCurrentGeneration(generation) {
  return generation.body === document.body && generation.frame === frameRenders && !retired.has(generation.body)
}

// The `#content` frame is about to be rendered: a new generation (called by
// `frame_hold.js` alone; "FRAME NAVIGATIONS" there, step 2).
export function frameRendered() { frameRenders += 1 }

// See "WHAT A GENERATION IS": `body` is about to be replaced (called by
// `queue.js`'s `turbo:before-render` listener alone).
export function retire(body) { retired.add(body) }

// THE CHAIN. `tail` is the promise the next write waits for; `queued` counts
// the writes waiting for their turn or in flight. Both are written by
// `acquire` (`queue_core.js`) alone, and read there (`idle`, `drain`).
let tail = Promise.resolve()
let queued = 0
// Every write ever queued on this document, counted: lets a `#content` frame
// navigation tell whether anything was written since its request went out
// (see "FRAME NAVIGATIONS" in `frame_hold.js`). Counted by `acquire`.
let writes = 0

export function chain() { return tail }
export function chainOnto(promise) { tail = promise }
export function writeQueued() {
  queued += 1
  writes += 1
}
export function writeLeft() { queued -= 1 }
export function queuedWrites() { return queued }
// Read by `frame_hold.js`, which compares two readings.
export function writeCount() { return writes }

// THE REGISTERED FORMS: the autosave controllers that `drained()` asks to
// flush (`registerForm` / `unregisterForm` in `queue_core.js` are the only
// writers). `registeredForms()` is a copy, safe to walk while a form
// unregisters itself.
const forms = new Set()

export function addForm(form) { forms.add(form) }
export function removeForm(form) { forms.delete(form) }
export function formCount() { return forms.size }
export function registeredForms() { return Array.from(forms) }

// THE PROMOTION WINDOW (`promotion_hold.js`, "THE PROMOTION HOLD", says what
// it is for). `promotion` is the record of an open window -- the presses held
// in it, by form, and the timer of its limit -- or null. It is opened and
// closed from `frame_hold.js`'s listeners (the frame's GET going out, its
// render) and closed from `promotion_hold.js`'s (the promoted visit's
// `turbo:load`, a failed fetch); `promotion_hold.js`'s `submit` listener
// fills `held`.
//
// What becomes of the held presses when the window closes is
// `promotion_hold.js`'s business ("AT RELEASE" there): it hands that in with
// `onPromotionEnd` as it is evaluated. `frame_hold.js` is evaluated before
// it (see the order in `queue.js`) and so cannot import it; both meet here.
// Until it has handed it in nothing can be held, and nothing is released.
//
// `frameFormRefused` is "WHICH RENDERS ARE PROMOTED" (`promotion_hold.js`):
// read and written by `frame_hold.js`'s listeners alone.
export const PROMOTION_LIMIT_MS = 500
export const PROMOTION_FETCH_LIMIT_MS = 10000
let promotion = null
let frameFormRefused = false
let release = () => {}

export function onPromotionEnd(callback) { release = callback }
export function promotionOpen() { return promotion !== null }
// The presses held in the open window (a `Map` keyed by the form), or null.
export function promotionHeld() { return promotion ? promotion.held : null }
export function frameFormWasRefused() { return frameFormRefused }
export function setFrameFormRefused(refused) { frameFormRefused = refused }

export function promotionStarts(limit) {
  clearTimeout(promotion?.timer)
  promotion = { held: promotion?.held || new Map(), timer: setTimeout(promotionEnds, limit) }
}

export function promotionEnds() {
  if (!promotion) return
  const { held, timer } = promotion
  promotion = null
  clearTimeout(timer)
  release(held)
}
