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
// own block form submissions -- add, duplicate, delete, the Undo toast -- and
// the editor header's `_top` actions (Publish, Unpublish, Schedule, Move to
// trash), which wait here so an edit still queued is saved BEFORE the action
// changes the record (`holdTurboRequest`).
//
// Failure never blocks the queue. A task that throws releases its slot
// (`finally`) and the next goes; a fetch that never answers is cut by the
// caller's own timeout; a held Turbo request releases when its answer arrives
// OR errors OR is aborted OR its form leaves the DOM (see
// `holdTurboRequest`), and after `HOLD_LIMIT_MS` regardless.
//
// PAGE GENERATIONS. `generation` is bumped on every `turbo:before-visit` and
// `turbo:before-render` (a visit, a Reload, a locale switch, a restoration
// visit all render). A task carries the generation it was queued under: one
// that reaches the front of the queue after a bump is DROPPED unsent (its form
// is gone), and one already in flight is told (`isCurrent()`) so its answer
// writes no bases and renders no streams into the NEW document, whose
// `page-base-updated-at` has the same id. The chain itself is not reset by a
// bump: the new page's first request waits for the old page's in-flight one
// (bounded by its timeout) rather than racing it.
const HOLD_LIMIT_MS = 30000

let tail = Promise.resolve()
let generation = 0

// Returned by `enqueue` for a task dropped because the page it was queued on is gone.
export const CANCELLED = Symbol("autosave-cancelled")

// Resolves with a `release` function once every earlier holder has released.
// The next holder waits for exactly this one's release.
export function acquire() {
  let release
  const released = new Promise((resolve) => { release = resolve })
  const turn = tail.then(() => release)
  tail = tail.then(() => released)
  return turn
}

// Runs `task` (an async function, handed `isCurrent`) alone: returns its
// result, `CANCELLED` if the page changed while it waited, or rethrows its
// error -- and in every case lets the next one go.
export async function enqueue(task) {
  const queuedUnder = generation
  const release = await acquire()
  try {
    if (queuedUnder !== generation) return CANCELLED
    return await task(() => queuedUnder === generation)
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

// For a Turbo-driven request (`turbo:before-fetch-request`): holds it until
// the queue is free, lets `before` set its headers at send time, then keeps
// the queue's slot until the answer's bases are applied (`baseIds`).
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
//   a card re-rendered by a predecessor's stream), so a form-level listener
//   would never hear it. An event is accepted when it is for this form, or
//   for the document element while this form is gone;
// - `HOLD_LIMIT_MS` passes.
// `resume()` is always called, even if `before` throws, so Turbo's submission
// is never left waiting. A request whose page is gone (a generation bump while
// it waited) or that was already aborted just resumes at once, unmodified.
export function holdTurboRequest(event, { before = () => {}, baseIds = [], untilNavigation = false } = {}) {
  event.preventDefault()
  const target = event.target
  const request = event.detail
  const signal = request.fetchOptions?.signal
  const queuedUnder = generation

  acquire().then((release) => {
    if (signal?.aborted || queuedUnder !== generation) {
      release()
      request.resume()
      return
    }

    let finished = false
    const mine = (turboEvent) => turboEvent.target === target || (!target.isConnected && turboEvent.target === document.documentElement)
    const finish = () => {
      if (finished) return
      finished = true
      clearTimeout(limit)
      document.removeEventListener("turbo:before-fetch-response", onResponse)
      document.removeEventListener("turbo:fetch-request-error", onError)
      signal?.removeEventListener("abort", finish)
      navigationWaiters.delete(finish)
      release()
    }
    const onResponse = async (responseEvent) => {
      if (!mine(responseEvent)) return
      // `untilNavigation` (the header's Publish/Schedule/... actions): when
      // the answer is a redirect the page is about to be replaced, so the slot
      // is NOT released yet -- an autosave sent in between (a blur that
      // arrives after the click, a follow-up of one already in flight) would
      // run on the base the action just moved, get refused, and its answer be
      // rendered into the NEW document a frame later. It is released when the
      // new page starts rendering (`startNewGeneration`), by which time every
      // task still waiting has been dropped as belonging to the old page.
      if (untilNavigation && responseEvent.detail.fetchResponse.response.redirected) {
        navigationWaiters.add(finish)
        return
      }
      try {
        if (queuedUnder === generation) syncBases(await responseEvent.detail.fetchResponse.response.clone().text(), baseIds)
      } finally {
        finish()
      }
    }
    const onError = (errorEvent) => { if (mine(errorEvent)) finish() }
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

const navigationWaiters = new Set()
const startNewGeneration = () => {
  generation += 1
  Array.from(navigationWaiters).forEach((finish) => finish())
}
document.addEventListener("turbo:before-visit", startNewGeneration)
document.addEventListener("turbo:before-render", startNewGeneration)
