// One screen's writes, one at a time (cs-studio design pass round 2, Task 6
// fix round 1).
//
// WHY. Every write a page editor sends can move the page's `updated_at`: a
// block save, add, duplicate, delete and reorder all `touch` it. The page
// settings form holds that `updated_at` as its autosave base, and a stale
// base is now REFUSED (409, `Admin::AutosaveResponses#refuse_stale_autosave`).
// To keep the page form's base honest the server moves it forward in a block's
// answer -- but only when the base the request carried
// (`X-Page-Base-Updated-At`) was still current before that write. Two
// requests sent from the same screen at the same moment (the page form and
// every block form debounce on the same tick after "Use all"; or a block's
// answer still in flight on a slow connection when the next form sends) carry
// the same base: the first moves the page, the second's base is then stale, so
// no base is streamed back and its own touch moves the page again -- and the
// page form is left holding a base that nobody else made stale. Its next
// save is a 409 and the form is dead until Reload, losing the typed text.
//
// WHAT. This queue makes a request be SENT only after the previous one's
// answer has been received AND its base values written into the hidden fields
// (`syncBases`, synchronous -- `Turbo.renderStreamMessage` applies a stream on
// the next frame, too late for a request sent straight after). Each request
// therefore reads the freshest bases at SEND time (inside the task), never at
// queue time. The server's base mechanism is unchanged.
//
// Everything that sends `X-Page-Base-Updated-At` goes through here: every
// `admin--autosave` form (`enqueue`), block reorder (`enqueue`), Turbo's own
// block form submissions -- add, duplicate, delete, the Undo toast
// (`holdTurboRequest`) -- and, from outside the editor's forms, the page
// tree's move (`enqueue`) and its Undo toast (`holdTurboRequest`): moving the
// page that is open moves its `updated_at` like any other write to it
// (`admin--tree`).
//
// THE RULE (fix round 3; final fix wave 1): nothing that REPLACES AN EDITOR
// starts until the queue is empty. Three kinds of thing replace an editor:
// - a Turbo visit (a sidebar link, a locale switch, Reload);
// - the editor header's actions (Publish, Unpublish, Schedule, Move to trash,
//   which redirect), and any other Turbo form submission made while something
//   is outstanding (the Undo toast's button, New page / New post, sign out):
//   see "TURBO FORM SUBMISSIONS" at the end of this file;
// - a Turbo FRAME navigation inside `#content` (the page tree's links, the
//   header's breadcrumb, its menu's Activity link). Turbo fetches and RENDERS
//   the frame first and only then proposes the promoted visit, so by
//   `turbo:before-visit` the editor's forms are long gone -- their debounce
//   timers cleared, a save's follow-up skipped. This one is held twice: its
//   REQUEST (so the answer is not older than the saves it waited for -- the
//   link may lead back to the same record) and its RENDER (for edits that
//   land while the request is on its way). See "FRAME NAVIGATIONS" at the
//   end of this file.
// All of them wait on `drained()`: a promise that resolves when no task is
// queued or in flight AND no autosave form has a debounced, queued, in-flight
// or retrying save -- forms are asked to send what they hold (`flush()`) in a
// loop until a pass finds nothing new, bounded by `DRAIN_LIMIT_MS` -- the
// whole wait, including the wait for a request already on the wire (fix round
// 4: a save that never answers no longer holds a visit for its own 30 s
// timeout). It resolves to whether every form ended CLEAN (last answer a
// success, not paused by a 409, not failed).
// So no edit is dropped on the way out: before this, a queued save was either
// cancelled by the visit (lost silently) or sent on a base the action had just
// moved (refused). The header action additionally refuses to run when a form
// ended unclean (`admin--queue-hold`): its redirect would throw away the very
// text a 409 bar promised to keep. A plain visit or frame navigation still
// goes on (the editor chose to leave; do not trap them), after the drain.
//
// Failure never blocks the queue. A task that throws releases its slot
// (`finally`); a fetch that never answers is cut by the caller's own timeout;
// a held Turbo request releases when its answer arrives OR errors OR is
// aborted OR its form leaves the DOM (see `holdTurboRequest`), and after
// `HOLD_LIMIT_MS` regardless.
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
import { Turbo } from "@hotwired/turbo-rails"

const HOLD_LIMIT_MS = 30000
const DRAIN_LIMIT_MS = 10000
const STREAM_RENDER_LIMIT_MS = 1000
const VISIT_NOTE_LIMIT_MS = 2000

let tail = Promise.resolve()
// See "WHAT A GENERATION IS".
let frameRenders = 0
const retired = new WeakSet()
let queued = 0
// Every write ever queued on this document, counted: lets a `#content` frame
// navigation tell whether anything was written since its request went out
// (see "FRAME NAVIGATIONS").
let writes = 0
const forms = new Set()

// The page a controller was rendered on: read in `connect()`, handed back to
// `enqueue`. Opaque to the caller.
export function currentGeneration() { return { body: document.body, frame: frameRenders } }

// Whether that page is still the one showing.
export function isCurrentGeneration(generation) {
  return generation.body === document.body && generation.frame === frameRenders && !retired.has(generation.body)
}

// Autosave controllers register themselves so `drained()` can ask them to
// flush and report whether they ended clean. A form offers `flush(drain)`,
// `outstanding()` (debounced, queued, in flight, retrying) and `clean()`.
//
// The first form to register also puts up THE UNLOAD GUARD below, and the
// last to leave takes it down: a screen with no autosave form has nothing of
// this module's to lose (and the explicit-save screens have their own,
// `admin--save-bar`).
export function registerForm(form) {
  if (forms.size === 0) window.addEventListener("beforeunload", guardUnload)
  forms.add(form)
}
export function unregisterForm(form) {
  forms.delete(form)
  if (forms.size === 0) window.removeEventListener("beforeunload", guardUnload)
}

const idle = () => queued === 0 && !Array.from(forms).some((form) => form.outstanding())

// Nothing queued, in flight or waiting to be sent, and every form's last
// outcome clean.
export function settled() { return idle() && Array.from(forms).every((form) => form.clean()) }

// THE UNLOAD GUARD. Everything above and below is about Turbo replacing the
// editor, which this module can hold until the queue has drained. Closing the
// tab, reloading it or typing another address cannot be held: the document
// is gone as soon as the handler returns, a debounce timer never fires and a
// request on the wire may be cut. All there is, is the browser's own "Leave
// site?" dialog, which `preventDefault()` on `beforeunload` asks for. So it
// is asked for exactly when leaving would lose something -- when the screen
// is not `settled()`:
// - a write is queued or in flight, or a form holds an edit inside its
//   debounce or is waiting to retry (`busy()`);
// - or a form's last save did not land -- paused by a 409 "Changed
//   elsewhere", refused, invalid, given up on after the retries, signed out
//   (`clean()` false). The typed text is then in the page and nowhere else;
//   the 409 bar says in so many words that it is still there to be copied.
// Never on a clean screen, and never once a save has been answered with a
// success: asked every time, the dialog would be dismissed unread the one
// time it mattered. Nothing is sent from here -- a request started while the
// page unloads is not reliably delivered, and the prompt is what gives the
// debounce and the queue the time to finish when the editor chooses to stay.
//
// A Turbo visit fires no `beforeunload`, so the Reload link of the 409 bar
// (how that text is given up on purpose) and every link inside CS Studio
// stay under "THE RULE" alone.
function guardUnload(event) {
  if (!settled()) event.preventDefault()
}

// True while any write is queued, in flight, or still held by a form.
export function busy() { return !idle() }

// Resolves when `promise` does or after `ms`, whichever is first.
function within(promise, ms) {
  let timer
  const limit = new Promise((resolve) => { timer = setTimeout(resolve, Math.max(ms, 0)) })
  return Promise.race([ promise, limit ]).finally(() => clearTimeout(timer))
}

// See "THE RULE" above. Never waits longer than `limit` in all: the wait for
// the chain itself is raced against what is left of it, so a request that
// does not answer cannot hold the caller past the deadline. Whatever is left
// behind then still runs, in order, and finds `isCurrent()` false once the
// page is gone. `token` is this call's own: a form uses it to send a
// retry that is waiting out its backoff at most ONCE per drain (see
// `admin--autosave#flush`).
//
// It NEVER REJECTS (follow-up N3). Everything that waits on it holds something
// of Turbo's -- a visit, a frame's request or render, a form submission -- and
// lets it go in a `then`: a rejection would strand that for good, the editor
// left on a page whose links and buttons do nothing. A form whose `flush`
// throws is skipped (its edit is then only sent by its own timer); anything
// else that throws ends the wait at once, reported as unclean.
export function drained(options) {
  return drain(options).catch(() => ({ clean: false, timedOut: false }))
}

async function drain({ limit = DRAIN_LIMIT_MS } = {}) {
  const deadline = Date.now() + limit
  const token = {}
  let timedOut = false

  for (;;) {
    Array.from(forms).forEach((form) => { try { form.flush(token) } catch { /* see `drained` */ } })
    await within(tail, deadline - Date.now())
    await new Promise((resolve) => setTimeout(resolve, 25))
    if (idle()) break
    if (Date.now() >= deadline) { timedOut = true; break }
  }

  return { clean: !timedOut && Array.from(forms).every((form) => form.clean()), timedOut }
}

// Resolves with a `release` function once every earlier holder has released.
// The next holder waits for exactly this one's release.
export function acquire() {
  let release
  const released = new Promise((resolve) => { release = resolve })
  queued += 1
  writes += 1
  const turn = tail.then(() => release)
  tail = tail.then(() => released).then(() => { queued -= 1 })
  return turn
}

// Runs `task` (an async function, handed `isCurrent`) alone: returns its
// result or rethrows its error -- and in every case lets the next one go.
// `generation` is the page the task belongs to (the caller's
// `currentGeneration()` at connect -- see "PAGE GENERATIONS"); left out, it is
// the page showing as the task is queued.
export async function enqueue(task, { generation: belongsTo = currentGeneration() } = {}) {
  const release = await acquire()
  try {
    return await task(() => isCurrentGeneration(belongsTo))
  } finally {
    release()
  }
}

// Copies each named base field's fresh value out of a Turbo Stream answer onto
// the live hidden field, synchronously. Matched by id (a block's answer may
// carry both its own base and the page form's).
export function syncBases(streamText, ids) {
  const templates = Array.from(new DOMParser().parseFromString(streamText, "text/html").querySelectorAll("template"))
  for (const id of ids) {
    const field = document.getElementById(id)
    if (!field) continue
    const fresh = templates
      .map((template) => template.content.querySelector(`[name="base_updated_at"][id="${id}"]`))
      .find((candidate) => candidate)?.value
    if (fresh) field.value = fresh
  }
}

// Lets a caller wait until Turbo has APPLIED a Turbo Stream answer it is
// about to render itself (see `holdTurboRequest`). Turbo appends the answer's
// `<turbo-stream>` elements to the document; each dispatches
// `turbo:before-stream-render` as it connects -- all of them in that one
// append -- and performs its action after the next repaint (`StreamElement
// #render`, turbo-rails 2.0.23; a timer instead when the tab is hidden).
// `applied(text)` resolves once every stream element OF THAT ANSWER has been
// seen since this was created, plus that repaint and the task after it.
//
// "Of that answer" (follow-up N5): the event is heard on `document`, where
// every stream on the page passes -- a translation suggestion arriving in the
// same moment (`admin--translate` renders its own), a toast. Counting events
// let a foreign stream stand in for the held answer's and release the slot
// before the card was in the list. The held answer is rendered by Turbo, so
// its elements cannot be tagged beforehand; they are recognised by their
// markup instead: each stream seen is kept as its `outerHTML`, and the wait
// ends when the answer's own streams (parsed from the same text, so the same
// markup) are all among them, each matched once. Turbo may render before or
// after this caller has read the body, hence the list rather than a count
// from "now".
//
// Never longer than `STREAM_RENDER_LIMIT_MS`: an answer Turbo does not render
// after all (the form's page is gone) must not hold the queue.
function streamRenders() {
  const seen = []
  let check = () => {}
  const note = (event) => { seen.push(event.target.outerHTML); check() }
  document.addEventListener("turbo:before-stream-render", note)

  return {
    stop: () => document.removeEventListener("turbo:before-stream-render", note),
    async applied(streamText) {
      const expected = Array.from(new DOMParser().parseFromString(streamText, "text/html").querySelectorAll("turbo-stream"), (stream) => stream.outerHTML)
      if (expected.length === 0) return

      await within(new Promise((resolve) => {
        check = () => {
          const pool = seen.slice()
          const all = expected.every((markup) => {
            const index = pool.indexOf(markup)
            if (index < 0) return false
            pool.splice(index, 1)
            return true
          })
          if (all) resolve()
        }
        check()
      }), STREAM_RENDER_LIMIT_MS)
      await new Promise((resolve) => (document.visibilityState === "hidden" ? setTimeout(resolve, 0) : requestAnimationFrame(resolve)))
      await new Promise((resolve) => setTimeout(resolve, 0))
    }
  }
}

// For a Turbo-driven block request (add, duplicate, delete, the Undo toast;
// `turbo:before-fetch-request`) and the tree move's Undo: holds it until the
// queue is free, lets `before` set its headers at send time, then keeps the
// queue's slot until the answer's bases (`baseIds`) and its streams are
// applied.
//
// When the slot is released -- checked against Turbo's own source (turbo-rails
// 2.0.23), not assumed:
// - the answer arrives (`turbo:before-fetch-response`) AND, when it is a
//   Turbo Stream, Turbo has applied it (`streamRenders`; ledger b6). The bases
//   are in the hidden fields at once, but the stream itself -- the card an
//   Add or Duplicate inserts, the one a Delete removes, the list an Undo
//   re-renders -- is applied a frame later, and the next task may read the
//   DOM: a reorder lists the cards as it is SENT, and sent in that gap it
//   listed them without the new card (422, the unsaved order left on screen);
// - or the request errors (`turbo:fetch-request-error`);
// - the request is ABORTED. Turbo cancels the previous form submission when a
//   new one starts (`Navigator#submitForm`), and `FetchRequest#perform`
//   swallows the `AbortError` without dispatching any event, so the request's
//   own signal (`fetchOptions.signal`) is listened to;
// - those events are listened for on `document`, not on the form: Turbo's
//   `dispatch` sends an event to `document.documentElement` instead when the
//   target is no longer connected (the Undo toast auto-dismissed mid-request,
//   a card re-rendered by a predecessor's stream). For that case only, an
//   event is accepted as this request's by what identifies it: the answer by
//   its URL, or by being a redirected one (a block action answers with a
//   stream, but an expired session answers with a redirect to sign-in, whose
//   final URL is not the request's -- unmatched, the slot stayed held for the
//   whole `HOLD_LIMIT_MS`); the error by the request's own abort signal --
//   never "any event on the document element", which would also match
//   another request's;
// - `HOLD_LIMIT_MS` passes.
// `resume()` is always called, even if `before` throws, so Turbo's submission
// is never left waiting. A request whose page is gone (replaced while
// it waited) or that was already aborted just resumes at once, unmodified.
export function holdTurboRequest(event, { before = () => {}, baseIds = [] } = {}) {
  event.preventDefault()
  const target = event.target
  const request = event.detail
  const signal = request.fetchOptions?.signal
  const queuedUnder = currentGeneration()
  const url = request.url?.href

  acquire().then((release) => {
    if (signal?.aborted || !isCurrentGeneration(queuedUnder)) {
      release()
      request.resume()
      return
    }

    let finished = false
    const gone = () => !target.isConnected
    const isMyResponse = (e) => {
      if (e.target === target) return true
      const response = e.detail.fetchResponse?.response
      return gone() && e.target === document.documentElement && (response?.url === url || Boolean(response?.redirected))
    }
    const isMyError = (e) => e.target === target || (gone() && e.target === document.documentElement && e.detail.request?.abortSignal === signal)
    const finish = () => {
      if (finished) return
      finished = true
      clearTimeout(limit)
      document.removeEventListener("turbo:before-fetch-response", onResponse)
      document.removeEventListener("turbo:fetch-request-error", onError)
      signal?.removeEventListener("abort", finish)
      release()
    }
    const onResponse = async (responseEvent) => {
      if (!isMyResponse(responseEvent)) return
      // From now, before anything is awaited: Turbo reads the same body and
      // renders it on its own schedule.
      const renders = streamRenders()
      try {
        const response = responseEvent.detail.fetchResponse.response
        const text = await response.clone().text()
        if (isCurrentGeneration(queuedUnder)) syncBases(text, baseIds)
        if ((response.headers.get("Content-Type") || "").includes("text/vnd.turbo-stream.html")) await renders.applied(text)
      } finally {
        renders.stop()
        finish()
      }
    }
    const onError = (errorEvent) => { if (isMyError(errorEvent)) finish() }
    const limit = setTimeout(finish, HOLD_LIMIT_MS)

    document.addEventListener("turbo:before-fetch-response", onResponse)
    document.addEventListener("turbo:fetch-request-error", onError)
    signal?.addEventListener("abort", finish, { once: true })
    try {
      before(request)
    } finally {
      request.resume()
    }
  })
}

// A Turbo visit (sidebar link, locale switch, Reload) waits for the queue to
// drain first, so no edit still on its way is lost to the page replacing
// itself. Only when something IS outstanding: with nothing queued the visit
// goes straight on, so screens without autosave (and `admin--save-bar`'s own
// before-visit guard) are untouched. After the drain the visit goes on
// whatever the outcome -- the editor chose to leave, and is never trapped on
// the page (a timeout, a refused or failed save still end in the visit; the
// 409 bar and the leave handling already say what was not saved). `reentry`
// lets the visit this handler starts through without being intercepted again.
//
// Two visits are never held, because holding one means issuing it again with
// `Turbo.visit(url)`, and each of them arrives WITH the answer Turbo already
// fetched -- a second fetch of a page that is, or is about to be, on screen:
// - the redirect that answers a Turbo form submission (`answered`, see
//   "TURBO FORM SUBMISSIONS" below). The flash -- the "Moved to trash · Undo"
//   toast, "Restored …" -- was spent on the first fetch;
// - the visit a `#content` frame navigation is promoted to (`promoted`, the
//   frame's own URL, noted as the frame is let render below). It replaces
//   nothing: the frame has rendered. Held, the page a tree link had just
//   loaded was loaded a second time, and the old page's answer drawn into it
//   in between (review B, M1). Normally nothing is outstanding by then anyway
//   -- the frame's request and render waited for the drain.
// Each note is the URL that visit will have. A note is spent on the next
// `turbo:before-visit`, whichever visit it is, and EXPIRES after
// `VISIT_NOTE_LIMIT_MS` (follow-up N2): Turbo proposes the visit within
// moments of the event the note is taken at, and not every such event is
// followed by one (a frame form re-rendered in place after a 422 is promoted
// to nothing new; a redirected submission inside a frame may end in the
// frame). A note left lying would excuse the editor's NEXT visit to exactly
// that URL from the drain. No note is taken without a URL (a frame with no
// `src`).
let reentry = false
const expectedVisits = { promoted: null, answered: null }
const noteTimers = {}
const absolute = (url) => { try { return new URL(url, document.baseURI).href } catch { return null } }
function expectVisit(kind, url) {
  clearTimeout(noteTimers[kind])
  expectedVisits[kind] = url ? absolute(url) : null
  if (expectedVisits[kind]) noteTimers[kind] = setTimeout(() => { expectedVisits[kind] = null }, VISIT_NOTE_LIMIT_MS)
}

document.addEventListener("turbo:before-visit", (event) => {
  const expected = Object.values(expectedVisits).filter(Boolean)
  expectVisit("promoted", null)
  expectVisit("answered", null)
  if (expected.includes(absolute(event.detail.url))) return
  if (reentry || event.defaultPrevented || !busy()) return

  event.preventDefault()
  const url = event.detail.url
  drained().then(() => {
    reentry = true
    try {
      Turbo.visit(url)
    } finally {
      reentry = false
    }
  })
})

// FRAME NAVIGATIONS inside `#content` replace the editor exactly as a visit
// does (see "THE RULE"), but Turbo fetches and renders the frame BEFORE it
// proposes the promoted visit, so the drain cannot hang on
// `turbo:before-visit`. It hangs on the frame's own two steps.
//
// 1. THE REQUEST (follow-up N1; the `window` listener further down, which
//    holds a GET carrying `Turbo-Frame: content` like it holds a write). The
//    link may lead back to the record that is open -- the open page's own row
//    in the tree is such a link. Were only the render held, the GET would go
//    out before the drain and answer with the record as it was BEFORE the
//    saves the render then waits for: the saved text gone from the field,
//    the old base in the form, the next edit a final 409. Held until
//    `drained()`, the answer is fetched after everything outstanding was
//    saved. While it waits the outgoing forms are connected, so `flush()`
//    sends debounced edits and a save's follow-up goes out. A prefetch
//    (`X-Sec-Purpose: prefetch`) is never held -- it replaces nothing -- and
//    a prefetched answer Turbo was about to reuse for a held request is
//    dropped: it was fetched on hover, before the drain. (The editors switch
//    link prefetching off altogether, `turbo-prefetch` in their head, for the
//    same reason on the visit path.)
//
// 2. THE RENDER (`turbo:before-frame-render`, cancelable, carries `resume`;
//    turbo-rails 2.0.23, `FrameController#allowsImmediateRender`). Two jobs:
//    - it is the page change (`frameRenders`), counted just before it
//      happens, so the outgoing forms' late answers draw nothing into the
//      editor that comes in; and the promoted visit's URL is noted;
//    - an edit can still land while the request is on its way -- still being
//      saved as the answer arrives, or saved already. Either way the answer
//      in hand is STALE in the same way as above: fetched before that save.
//      `writes` (every write queued, counted) is noted as the request goes
//      out (`frameRequestedAt`); a different count here, or a busy queue,
//      means stale. The render then waits for the drain, and the answer is
//      not rendered: the frame's URL is fetched again
//      (`fetchFrame`, a plain `fetch` with the same `Turbo-Frame` header)
//      and its `<turbo-frame id="content">` rendered in the stale one's
//      place (`event.detail.render` is wrapped at dispatch; Turbo takes the
//      renderer from the event synchronously). An edit landing during THAT
//      fetch gets one more round; after it a last drain, and the render goes
//      on whatever the outcome -- like a visit, the editor is never trapped.
//      If the second fetch fails or has no such frame (signed out, offline),
//      the answer Turbo has is rendered after all. A flash the first answer
//      relayed as a toast is not in the second: accepted, the edit matters
//      more. The promoted visit still carries the first answer, but it
//      renders nothing (`willRender: false`).
//
// With nothing outstanding neither step is touched. Only `#content`: the
// lazily loaded dialog frames (New page / New post), the ⌘K results and the
// media picker's library replace no editor.
async function fetchFrame(frame) {
  const url = frame.getAttribute("src")
  if (!url) return null

  try {
    const response = await fetch(url, {
      headers: { "Turbo-Frame": frame.id, Accept: "text/html, application/xhtml+xml" },
      signal: AbortSignal.timeout(DRAIN_LIMIT_MS)
    })
    if (!response.ok) return null
    return new DOMParser().parseFromString(await response.text(), "text/html").querySelector(`turbo-frame#${frame.id}`)
  } catch {
    return null
  }
}

let frameRequestedAt = null
document.addEventListener("turbo:before-frame-render", (event) => {
  const frame = event.target
  if (frame.id !== "content" || event.defaultPrevented) return

  const rendering = () => {
    frameRenders += 1
    expectVisit("promoted", frame.getAttribute("src"))
  }
  let fetchedAt = frameRequestedAt
  frameRequestedAt = null
  const stale = () => busy() || (fetchedAt !== null && fetchedAt !== writes)
  if (!stale()) return rendering()

  event.preventDefault()
  let fresh = null
  const render = event.detail.render
  event.detail.render = (current, answered) => render(current, fresh || answered)

  const settle = async () => {
    for (let round = 0; round < 2 && stale(); round += 1) {
      await drained()
      fetchedAt = writes
      fresh = (await fetchFrame(frame)) || fresh
    }
    if (busy()) await drained()
  }
  settle().catch(() => {}).then(() => {
    rendering()
    event.detail.resume()
  })
})

// TURBO FORM SUBMISSIONS (final fix wave 1, ledger q1). A Turbo form
// submission made from a screen with autosave forms may replace the editor
// (most answer with a redirect), so the rule applies to every one of them, in
// two halves -- generally, not form by form:
//
// 1. It is not SENT while anything is outstanding. `turbo:before-fetch-request`
//    for a non-GET request is held until `drained()`, then resumed whatever
//    the outcome, after `DRAIN_LIMIT_MS` at the latest. On `window`, so it
//    runs after every listener on an element or on `document`: a request
//    `holdTurboRequest` already took (block add/duplicate/delete, the reorder
//    and tree Undo toasts -- which also need the page base) is
//    `defaultPrevented` by then and left to it. The editor header's five
//    actions drain earlier still, at `submit` (`admin--queue-hold`), because
//    they also refuse to run after an unclean drain; this half only catches
//    what lands between their drain and their request.
//    (The same listener holds a `#content` frame's GET: "FRAME NAVIGATIONS",
//    step 1. Every other GET goes straight on.)
//
// 2. The visit its redirect ends in is not HELD. Turbo proposes that visit
//    with the answer it already has (`Navigator
//    #formSubmissionSucceededWithResponse`); held by the handler above it
//    would be issued again and fetched a second time, the flash spent on the
//    first. `turbo:submit-end` is dispatched BEFORE the visit is proposed
//    (the navigator awaits the body first), so the redirect's final URL is
//    noted there (`answered`) and that one visit let through. An edit that
//    lands between the submission and its answer is the price: its save
//    belongs to the page being replaced (sent if it was already on its way,
//    dropped if it was still inside its debounce).
//    The note cannot stick: it is replaced by every submission's end, spent
//    by the next `turbo:before-visit`, dropped by the next render, and
//    expires on its own (see `expectVisit`).
window.addEventListener("turbo:before-fetch-request", (event) => {
  if (event.defaultPrevented) return
  const { fetchOptions } = event.detail
  const headers = fetchOptions?.headers || {}
  const get = String(fetchOptions?.method || "GET").toUpperCase() === "GET"
  const frameGet = get && headers["Turbo-Frame"] === "content" && headers["X-Sec-Purpose"] !== "prefetch"
  if (get && !frameGet) return

  if (frameGet) {
    // The answer has to be newer than every write so far. A prefetched one
    // (Turbo's `LinkPrefetchObserver` hands it over on this same event) was
    // fetched on hover: dropped wherever there is a form it could be older
    // than.
    if (forms.size > 0) delete event.detail.fetchRequest
    frameRequestedAt = writes
  }
  if (!busy()) return

  event.preventDefault()
  drained().then(() => {
    if (frameGet) frameRequestedAt = writes
    event.detail.resume()
  })
})

document.addEventListener("turbo:submit-end", (event) => {
  const { success, fetchResponse } = event.detail
  expectVisit("answered", success && fetchResponse?.redirected ? fetchResponse.location : null)
})

// See "WHAT A GENERATION IS": the body Turbo is about to replace is retired
// now, a moment before the swap.
document.addEventListener("turbo:before-render", () => {
  if (Turbo.navigator?.currentVisit?.willRender === true) retired.add(document.body)
  expectVisit("answered", null)
})
