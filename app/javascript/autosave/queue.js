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
// `admin--autosave` form (`enqueue`), block reorder (`enqueue`), and Turbo's
// own block form submissions -- add, duplicate, delete, the Undo toast
// (`holdTurboRequest`).
//
// THE RULE (fix round 3; final fix wave 1): nothing that REPLACES AN EDITOR
// starts until the queue is empty. Three kinds of thing replace an editor:
// - a Turbo visit (a sidebar link, a locale switch, Reload);
// - the editor header's actions (Publish, Unpublish, Schedule, Move to trash,
//   which redirect);
// - a Turbo FRAME navigation inside `#content` (the page tree's links, the
//   header's breadcrumb, its menu's Activity link). Turbo fetches and RENDERS
//   the frame first and only then proposes the promoted visit, so by
//   `turbo:before-visit` the editor's forms are long gone -- their debounce
//   timers cleared, a save's follow-up skipped. This one is held on
//   `turbo:before-frame-render` (see the handler at the end of this file).
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

let tail = Promise.resolve()
// See "WHAT A GENERATION IS".
let frameRenders = 0
const retired = new WeakSet()
let queued = 0
// Set while an editor header action's own submission is on its way (see
// `beginAction`).
let actionInFlight = false
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
export function registerForm(form) { forms.add(form) }
export function unregisterForm(form) { forms.delete(form) }

const idle = () => queued === 0 && !Array.from(forms).some((form) => form.outstanding())

// Nothing queued, in flight or waiting to be sent, and every form's last
// outcome clean.
export function settled() { return idle() && Array.from(forms).every((form) => form.clean()) }

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
// page is gone. `drain` is this call's own token: a form uses it to send a
// retry that is waiting out its backoff at most ONCE per drain (see
// `admin--autosave#flush`).
export async function drained({ limit = DRAIN_LIMIT_MS } = {}) {
  const deadline = Date.now() + limit
  const drain = {}
  let timedOut = false

  for (;;) {
    Array.from(forms).forEach((form) => form.flush(drain))
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

// For a Turbo-driven block request (add, duplicate, delete, the Undo toast;
// `turbo:before-fetch-request`): holds it until the queue is free, lets
// `before` set its headers at send time, then keeps the queue's slot until the
// answer's bases are applied (`baseIds`).
//
// When the slot is released -- checked against Turbo's own source (turbo-rails
// 2.0.23), not assumed:
// - the answer arrives (`turbo:before-fetch-response`), or the request errors
//   (`turbo:fetch-request-error`);
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
      try {
        if (isCurrentGeneration(queuedUnder)) syncBases(await responseEvent.detail.fetchResponse.response.clone().text(), baseIds)
      } finally {
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
// - the redirect that answers an editor header action (`actionInFlight`). The
//   flash -- the "Moved to trash · Undo" toast -- was spent on the first
//   fetch. (An edit that lands between that submission and its answer is the
//   price: its save belongs to the page being replaced.) The flag is spent on
//   the first visit it lets through, so it never excuses a second one;
// - the visit a `#content` frame navigation is promoted to (`promotedVisit`,
//   the frame's own URL, set as the frame is let render below). It replaces
//   nothing: the frame has rendered. Held, the page a tree link had just
//   loaded was loaded a second time, and the old page's answer drawn into it
//   in between (review B, M1). Normally nothing is outstanding by then anyway
//   -- the frame's render waited for the drain. Spent on the next visit,
//   whichever it is.
let reentry = false
let promotedVisit = null
const absolute = (url) => { try { return new URL(url, document.baseURI).href } catch { return null } }
document.addEventListener("turbo:before-visit", (event) => {
  const promoted = promotedVisit
  promotedVisit = null
  if (promoted && promoted === absolute(event.detail.url)) return
  if (actionInFlight) {
    actionInFlight = false
    return
  }
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

// A frame navigation inside `#content` replaces the editor exactly as a visit
// does (see "THE RULE"), but Turbo renders the frame BEFORE it proposes the
// promoted visit, so the drain has to hang on the frame's render:
// `turbo:before-frame-render` is cancelable and carries `resume` (turbo-rails
// 2.0.23, `FrameController#allowsImmediateRender`). While the drain runs the
// outgoing forms are still connected, so `flush()` sends debounced edits and a
// save's follow-up goes out; the render then goes on whatever the outcome,
// after `DRAIN_LIMIT_MS` at the latest. With nothing outstanding the render
// is not touched. Either way the render is a page change (`frameRenders`):
// counted just before it happens, so the outgoing forms' late answers draw
// nothing into the editor that comes in.
//
// Only `#content`: the lazily loaded dialog frames (New page / New post), the
// ⌘K results and the media picker's library replace no editor.
document.addEventListener("turbo:before-frame-render", (event) => {
  const frame = event.target
  if (frame.id !== "content" || event.defaultPrevented) return

  const render = () => {
    frameRenders += 1
    promotedVisit = absolute(frame.getAttribute("src"))
  }
  if (!busy()) return render()

  event.preventDefault()
  drained().then(() => {
    render()
    event.detail.resume()
  })
})

// `admin--queue-hold` brackets a header action's real submission with these:
// `beginAction()` as it lets the submit through, `endAction()` when the
// submission ends without a redirect to follow (aborted, failed, refused).
// After a redirect the flag has to outlive `turbo:submit-end`, which Turbo
// dispatches BEFORE it proposes the redirect's visit
// (`Navigator#formSubmissionSucceededWithResponse` awaits the body first), so
// it is dropped by that visit's own `turbo:before-visit` above, and at the
// latest by the next render -- any render: it cannot stick past the page.
export function beginAction() { actionInFlight = true }
export function endAction() { actionInFlight = false }

// See "WHAT A GENERATION IS": the body Turbo is about to replace is retired
// now, a moment before the swap.
document.addEventListener("turbo:before-render", () => {
  if (Turbo.navigator?.currentVisit?.willRender === true) retired.add(document.body)
  actionInFlight = false
})
